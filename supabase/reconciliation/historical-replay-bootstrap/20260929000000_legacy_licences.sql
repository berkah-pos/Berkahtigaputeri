-- RECONSTRUCTED PRE-HISTORY PREREQUISITE FOR DISPOSABLE REPLAY ONLY.
-- The hosted ledger begins after this legacy relation existed. This is not an
-- original historical migration and must never be run against a hosted project.
-- No rows are seeded; the following 139 archived migration bodies replay unchanged.

CREATE TABLE public.licences (
  device_id text NOT NULL,
  toko_name text NOT NULL DEFAULT ''::text,
  package_id text NOT NULL,
  expiry_date date,
  max_user integer NOT NULL DEFAULT 5,
  features jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_blocked boolean NOT NULL DEFAULT false,
  toko_address text NOT NULL DEFAULT ''::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT licences_pkey PRIMARY KEY (device_id),
  CONSTRAINT licences_max_user_check CHECK (max_user > 0),
  CONSTRAINT licences_package_id_check CHECK (
    package_id = ANY (ARRAY['com.btp.uat'::text, 'com.btp.pos'::text])
  )
);

-- These two relations also existed before the recorded migration ledger.
-- The first recorded migration uses CREATE TABLE IF NOT EXISTS with older defaults,
-- constraints, and an obsolete client_status -> licences foreign key. Because those
-- CREATE TABLE statements do not evolve a pre-existing relation, reproduce the current
-- staging catalog shape here. This is schema-only prehistory; never apply to hosted DBs.
CREATE TABLE public.app_config (
  key text NOT NULL,
  value jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_config_pkey PRIMARY KEY (key)
);

CREATE TABLE public.client_status (
  device_id text NOT NULL,
  last_seen timestamp with time zone NOT NULL DEFAULT now(),
  app_version text NOT NULL DEFAULT 'unknown'::text,
  last_transaction_id text,
  sales_today bigint NOT NULL DEFAULT 0,
  hardware_mode text NOT NULL DEFAULT 'SIMULATED'::text,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT client_status_pkey PRIMARY KEY (device_id),
  CONSTRAINT client_status_hardware_mode_check CHECK (
    hardware_mode = ANY (ARRAY['SIMULATED'::text, 'REAL'::text])
  ),
  CONSTRAINT client_status_sales_today_check CHECK (sales_today >= 0)
);
