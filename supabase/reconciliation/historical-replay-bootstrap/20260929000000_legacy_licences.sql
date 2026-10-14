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
