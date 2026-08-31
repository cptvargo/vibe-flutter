-- Run this in the Supabase SQL editor (Dashboard → SQL Editor)
-- Adds the admin_api_key column to the servers table.
-- Only the server owner can read/write their own row (RLS already enforced).

ALTER TABLE servers ADD COLUMN IF NOT EXISTS admin_api_key text;
