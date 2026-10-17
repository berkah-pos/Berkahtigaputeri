#!/usr/bin/env python3
"""Race two real PostgreSQL connections against the same expected_version=1 CAS."""

from __future__ import annotations

import json
import os
import sys
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor

import psycopg


def connect():
    return psycopg.connect(
        host=os.environ.get("CENTRAL_DB_HOST", "127.0.0.1"),
        port=int(os.environ.get("CENTRAL_DB_PORT", "5432")),
        dbname=os.environ.get("CENTRAL_DB_DATABASE", "berkahpos_central_ci"),
        user=os.environ.get("CENTRAL_DB_USERNAME", "postgres"),
        password=os.environ.get("CENTRAL_DB_PASSWORD", "postgres"),
        autocommit=False,
    )


def main() -> int:
    suffix = uuid.uuid4().hex
    tenant_id = f"tenant_casrace_{suffix}"
    device_id = f"casrace_{suffix}"
    scope_id = device_id
    barrier = threading.Barrier(2)
    results: list[dict[str, object]] = []
    results_lock = threading.Lock()

    try:
        with connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SHOW server_version_num")
                server_version_num = int(cursor.fetchone()[0])
                if not 170000 <= server_version_num < 180000:
                    raise RuntimeError(f"Expected PostgreSQL 17; got server_version_num={server_version_num}")
                cursor.execute(
                    """
                    INSERT INTO tenants (id, data, template_id, created_at, updated_at)
                    VALUES (%s, NULL, 'BASIC', NOW(), NOW())
                    """,
                    (tenant_id,),
                )
                cursor.execute(
                    """
                    INSERT INTO device_registry
                        (device_id, tenant_id, owner_user_id, status, registered_at, created_at, updated_at)
                    VALUES (%s, %s, NULL, 'pending', NULL, NOW(), NOW())
                    """,
                    (device_id, tenant_id),
                )
                cursor.execute(
                    """
                    INSERT INTO device_configs
                        (device_id, tenant_id, config, version, created_at, updated_at)
                    VALUES (%s, %s, '{}'::jsonb, 1, NOW(), NOW())
                    """,
                    (device_id, tenant_id),
                )

        def contender(label: str) -> dict[str, object]:
            try:
                with connect() as connection:
                    with connection.cursor() as cursor:
                        barrier.wait(timeout=10)
                        cursor.execute(
                            """
                            UPDATE device_configs
                            SET config = jsonb_build_object('writer', %s::text),
                                version = version + 1,
                                updated_at = NOW()
                            WHERE device_id = %s AND version = 1
                            RETURNING version
                            """,
                            (label, device_id),
                        )
                        row = cursor.fetchone()
                        if row is None:
                            connection.commit()
                            result: dict[str, object] = {"writer": label, "won": False, "version": None}
                        else:
                            new_version = int(row[0])
                            cursor.execute(
                                """
                                INSERT INTO audit_events
                                    (actor_user_id, tenant_id, scope_type, scope_id, action,
                                     previous_version, new_version, previous_sha256, new_sha256,
                                     metadata, created_at)
                                VALUES (NULL, %s, 'device', %s, 'test.configuration.cas',
                                        1, %s, NULL, NULL, %s::jsonb, NOW())
                                """,
                                (tenant_id, scope_id, new_version, json.dumps({"writer": label})),
                            )
                            connection.commit()
                            result = {"writer": label, "won": True, "version": new_version}
                with results_lock:
                    results.append(result)
                return result
            except BaseException:
                barrier.abort()
                raise

        with ThreadPoolExecutor(max_workers=2) as pool:
            contenders = [pool.submit(contender, "writer_a"), pool.submit(contender, "writer_b")]
            returned = [future.result(timeout=20) for future in contenders]

        with connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT version, config FROM device_configs WHERE device_id = %s", (device_id,))
                row = cursor.fetchone()
                cursor.execute("SELECT count(*) FROM audit_events WHERE scope_id = %s AND action = 'test.configuration.cas'", (scope_id,))
                audit_count = int(cursor.fetchone()[0])

        assert row is not None, "race row disappeared"
        assert int(row[0]) == 2, f"exactly one CAS winner expected, found version={row[0]}"
        assert sum(bool(result["won"]) for result in returned) == 1, returned
        assert audit_count == 1, f"audit event must commit atomically once; found {audit_count}"
        assert len(results) == 2, results

        report = {
            "status": "PASS",
            "postgresql_server_version_num": server_version_num,
            "writers": returned,
            "final_version": int(row[0]),
            "audit_rows_for_race": audit_count,
            "invariant": "exactly one expected_version=1 compare-and-set succeeds; losing attempt produces no update or audit row",
        }
        report_path = os.environ.get("CAS_RESULT_PATH")
        if report_path:
            with open(report_path, "w", encoding="utf-8") as output:
                json.dump(report, output, indent=2, sort_keys=True)
                output.write("\n")
        print(json.dumps(report, sort_keys=True))
        return 0
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    finally:
        try:
            with connect() as connection:
                with connection.cursor() as cursor:
                    cursor.execute("DELETE FROM audit_events WHERE scope_id = %s AND action = 'test.configuration.cas'", (scope_id,))
                    cursor.execute("DELETE FROM device_configs WHERE device_id = %s", (device_id,))
                    cursor.execute("DELETE FROM device_registry WHERE device_id = %s", (device_id,))
                    cursor.execute("DELETE FROM tenants WHERE id = %s", (tenant_id,))
        except Exception as cleanup_error:
            print(f"WARNING: disposable concurrency cleanup failed: {cleanup_error}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
