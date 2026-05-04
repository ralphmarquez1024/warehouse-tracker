-- =====================================================
-- WarehouseTracker — Supabase / PostgreSQL Schema
-- =====================================================
-- Run this in your Supabase SQL Editor:
--   1. Go to https://app.supabase.com → your project
--   2. SQL Editor → New query → paste this whole file → Run
-- =====================================================

-- ─────────────────────────────────────────────────────
-- TABLES
-- ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.products (
    id            BIGSERIAL PRIMARY KEY,
    brand         TEXT NOT NULL,
    part_number   TEXT NOT NULL,
    name          TEXT NOT NULL,
    category      TEXT NOT NULL DEFAULT 'Uncategorized',
    sources       TEXT[] DEFAULT ARRAY[]::TEXT[],
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    updated_at    TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (brand, part_number)
);
CREATE INDEX IF NOT EXISTS idx_products_brand    ON public.products(brand);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category);

CREATE TABLE IF NOT EXISTS public.inventory_items (
    id                BIGSERIAL PRIMARY KEY,
    serial_number     TEXT NOT NULL UNIQUE,
    product_id        BIGINT NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    shelf             TEXT,
    status            TEXT NOT NULL DEFAULT 'in'
                       CHECK (status IN ('in','out','notcheckedin')),
    checked_out_by    TEXT,
    checked_out_dept  TEXT,
    so_number         TEXT,
    last_scan         TEXT,
    created_at        TIMESTAMPTZ DEFAULT NOW(),
    updated_at        TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inv_status  ON public.inventory_items(status);
CREATE INDEX IF NOT EXISTS idx_inv_product ON public.inventory_items(product_id);
CREATE INDEX IF NOT EXISTS idx_inv_serial  ON public.inventory_items(serial_number);

CREATE TABLE IF NOT EXISTS public.scan_logs (
    id          BIGSERIAL PRIMARY KEY,
    log_time    TEXT NOT NULL,
    code        TEXT,
    message     TEXT,
    log_type    TEXT DEFAULT 'info'
                 CHECK (log_type IN ('in','out','warn','info')),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_logs_created ON public.scan_logs(created_at DESC);

CREATE TABLE IF NOT EXISTS public.upload_history (
    id           BIGSERIAL PRIMARY KEY,
    filename     TEXT NOT NULL,
    sheets       INT,
    sheet_names  TEXT[],
    added        INT,
    updated_cnt  INT,
    total        INT,
    upload_time  TEXT,
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────
-- HELPER FUNCTION: detect admin role from auth.users metadata
-- ─────────────────────────────────────────────────────
-- An admin is any auth user whose JWT contains role='admin' in
-- their app_metadata. We set that via the dashboard or SQL when
-- creating the admin account.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin',
    FALSE
  );
$$;

-- ─────────────────────────────────────────────────────
-- AUTO-UPDATE updated_at on products & inventory_items
-- ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_touch ON public.products;
CREATE TRIGGER trg_products_touch
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS trg_inv_touch ON public.inventory_items;
CREATE TRIGGER trg_inv_touch
  BEFORE UPDATE ON public.inventory_items
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ─────────────────────────────────────────────────────
-- ROW LEVEL SECURITY (the actual security boundary)
-- ─────────────────────────────────────────────────────
-- The frontend has the anon key embedded in plain HTML —
-- that's expected. Security is enforced HERE, in the database.
-- ANY visitor (anonymous or authenticated) can SELECT.
-- ONLY authenticated admins can INSERT/UPDATE/DELETE.

ALTER TABLE public.products         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_items  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_logs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.upload_history   ENABLE ROW LEVEL SECURITY;

-- products
DROP POLICY IF EXISTS "products_read"  ON public.products;
DROP POLICY IF EXISTS "products_admin" ON public.products;
CREATE POLICY "products_read" ON public.products
  FOR SELECT USING (TRUE);
CREATE POLICY "products_admin" ON public.products
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- inventory_items
DROP POLICY IF EXISTS "inv_read"  ON public.inventory_items;
DROP POLICY IF EXISTS "inv_admin" ON public.inventory_items;
CREATE POLICY "inv_read" ON public.inventory_items
  FOR SELECT USING (TRUE);
CREATE POLICY "inv_admin" ON public.inventory_items
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- scan_logs (admin-only read AND write — viewers don't see logs)
DROP POLICY IF EXISTS "logs_admin" ON public.scan_logs;
CREATE POLICY "logs_admin" ON public.scan_logs
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- upload_history (admin only)
DROP POLICY IF EXISTS "upload_admin" ON public.upload_history;
CREATE POLICY "upload_admin" ON public.upload_history
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- =====================================================
-- SEED DATA — 298 components from all_components_categorized.xlsx
-- =====================================================
INSERT INTO public.products (brand, part_number, name, category, sources) VALUES
  ('Siemens', '6ES7 212-1AE40-0XB0', 'Siemens SIMATIC S7-1200 PLC (CPU 1212C)', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7 214-1AG40-0XB0', 'Siemens SIMATIC S7-1200 PLC (CPU 1214C)', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7 515-2AM01-0AB0', 'Siemens SIMATIC S7-1500 PLC (CPU 1515-2 PN)', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', 'ED1052-1MD00-0BA7', 'Siemens LOGO! 8', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7 288-1SR40-0AA1', 'Siemens S7-200 SMART CPU SR20', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6EP3333-8SB00-0AY0', 'Siemens SITOP 24V 120W Power Supply', 'Power Supply & UPS', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6EP1323-2BA00', 'Siemens SITOP PSU100C 24V', 'Power Supply & UPS', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6EP1931-2DC31', 'Siemens SITOP DC UPS Module', 'Power Supply & UPS', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6EP1961-2BA00', 'Siemens SITOP Select Module', 'Power Supply & UPS', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6AV2123-2DB03-0AX0', 'Siemens KTP400 Basic HMI', 'HMI & Displays', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6AV2123-2GA03-0AX0', 'Siemens KTP700 Basic HMI', 'HMI & Displays', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6AV2124-0GC01-0AX0', 'Siemens TP700 Comfort HMI', 'HMI & Displays', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RT2017-1AP01', 'Siemens SIRIUS Contactor', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RT2018-1AP02', 'Siemens SIRIUS Contactor', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RT2035-1AL20', 'Siemens SIRIUS Contactor', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RU1900-2AM71', 'Siemens Thermal Overload Relay', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RU2116-1KB0', 'Siemens Overload Relay', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RU2116-1HB0', 'Siemens Overload Relay', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '5SL6104-6', 'Siemens MCB 4A', 'Circuit Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '5SL4506-8', 'Siemens MCB 6A', 'Circuit Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '5SY4106-7', 'Siemens MCB 6A', 'Circuit Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SU1050-0BB20-0AA0', 'Siemens Push Button', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SU1000-0AB40-0AA0', 'Siemens Push Button', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SB3400-1PA', 'Siemens Push Button', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7132-6HD01-0BB1', 'Siemens Relay Output Module', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7132-6HB00-0XB0', 'Siemens Digital Output Relay Module', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7136-6BA00-0CA0', 'Siemens Relay Module', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RT1955-4G', 'Siemens Terminal Block (for contactor)', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '8WH1000-0AF00', 'Siemens Terminal Block', 'Terminal Blocks & Accessories', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '8WH2000-0AG00', 'Siemens Terminal Block', 'Terminal Blocks & Accessories', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SB2200-6AA20', 'Siemens Pilot Lamp', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SU1051-6AA40-0AA0', 'Siemens LED Pilot Lamp', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7223-1BL32-0XB0', 'Siemens S7-1200 Digital I/O Module (DI/DO)', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7231-4HF32-0XB0', 'Siemens S7-1200 Analog Input Module', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7290-6AA30-0XA0', 'Siemens S7-1200 Signal Board', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7954-8LC03-0AA0', 'Siemens SIMATIC Memory Card', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RH2122-1BB40', 'Siemens Auxiliary Relay', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RH2911-1FA22', 'Siemens Auxiliary Contact Block', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3TX7004-1LB00', 'Siemens Interface Relay Module', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RV2011-1HA10', 'Siemens Motor Protection Circuit Breaker', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RV2021-1FA10', 'Siemens MPCB 6.3A', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RV2031-4EA10', 'Siemens MPCB 32A', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RP1505-1BW30', 'Siemens Time Relay', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3UG4511-1BP20', 'Siemens Voltage Monitoring Relay', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3UG4633-1AW30', 'Siemens Phase Monitoring Relay', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SK1111-1AB30', 'Siemens Safety Relay', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SB3500-1QA', 'Siemens Emergency Stop Push Button', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '8WD4408-0AF', 'Siemens Signal Column Light', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SU1900-0KK10-0AA0', 'Siemens Mounting Adapter', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RG4013-3AG01', 'Siemens Inductive Proximity Sensor', 'Sensors', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SB3921-0AA', 'Siemens Contact Block', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3SU1400-1AA10-1CA0', 'Siemens Illuminated Push Button', 'Pushbuttons & Signaling', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3UF7010-1AU00-0', 'Siemens Motor Management Relay', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RA2921-1AA00', 'Siemens Link Module (Star-Delta)', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RA6120-1BB32', 'Siemens Compact Starter', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK5204-0BA00-2AA3', 'Siemens SCALANCE XC204 Managed Switch', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK5104-0BA00-2AA3', 'Siemens SCALANCE XB004 Ethernet Switch', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK1901-1BB10-2AA0', 'Siemens Industrial Ethernet Cable', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7 972-0CB20-0XA0', 'Siemens PROFIBUS Connector', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK1571-0BA00-0AA0', 'Siemens USB Adapter for PROFIBUS', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6EP1334-2BA20', 'Siemens SITOP PSU100M 24V Power Supply', 'Power Supply & UPS', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6EP1961-3BA21', 'Siemens SITOP Redundancy Module', 'Power Supply & UPS', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7 953-8LP31-0AA0', 'Siemens SIMATIC Micro Memory Card', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-5BB13-7UV1', 'Siemens SINAMICS V20 0.37kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-5BB17-5UV1', 'Siemens SINAMICS V20 0.75kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-1KE11-8UF2', 'Siemens SINAMICS G120C 1.1kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-5BB21-5UV1', 'Siemens SINAMICS V20 1.5kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-5BB22-2UV1', 'Siemens SINAMICS V20 2.2kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-5BB25-5UV1', 'Siemens SINAMICS V20 5.5kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-5BB27-5UV1', 'Siemens SINAMICS V20 7.5kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-1KE12-3UF2', 'Siemens SINAMICS G120C 1.5kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-1KE14-3UF2', 'Siemens SINAMICS G120C 4.0kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-1KE15-8UF2', 'Siemens SINAMICS G120C 5.5kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-1KE17-5UF2', 'Siemens SINAMICS G120C 7.5kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-1KE21-3UF2', 'Siemens SINAMICS G120C 11kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-1KE21-7UF2', 'Siemens SINAMICS G120C 15kW', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK7243-1GX30-0XE0', 'Siemens S7-1200 Communication Module (GPRS)', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7543-1AX00-0XE0', 'Siemens S7-1500 Communication Module', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK5005-0BA10-1AB2', 'Siemens SCALANCE XB005 Ethernet Switch', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK5208-0BA10-2AA3', 'Siemens SCALANCE XC208 Managed Switch', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK5216-0BA00-2AA3', 'Siemens SCALANCE XC216 Managed Switch', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK5324-0BA00-2AA3', 'Siemens SCALANCE XC324 Managed Switch', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK5788-2GD00-0AB0', 'Siemens SCALANCE W788-2 Wireless Access Point', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK7243-2AX30-0XE0', 'Siemens S7-1200 PROFIBUS CM 1242-5', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK7243-5DX30-0XE0', 'Siemens S7-1200 RS485 CM 1241', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6GK1500-0FC10', 'Siemens PROFIBUS Bus Connector 90 Degree', 'Networking & Communication', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RA6120-0AB30', 'C-STARTER;DOL;0,1-0,4A;TERMINALLESS', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RA6250-2EP32', 'C-STARTER;REVRS.;8,0-32A;SPR.LOADED', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RA6250-1EB34', 'C-STARTER;REVRS.;8,0-32A;SCREW TYPE', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7 215-1AG40-0XB0', 'Siemens SIMATIC S7-1200 PLC (CPU 1215C)', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7 522-1BH01-0AB0', 'Siemens S7-1500 Digital Output Module (DQ 16×24VDC)', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7 521-1BH00-0AB0', 'Siemens S7-1500 Digital Input Module (DI 16×24VDC)', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6ES7 531-7KF00-0AB0', 'Siemens S7-1500 Analog Input Module (AI 8×U/I/RTD/TC)', 'PLC & Controllers', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6AV2124-0MC01-0AX0', 'Siemens TP1200 Comfort HMI (12" Touch Panel)', 'HMI & Displays', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '6SL3210-5BE21-5UV0', 'Siemens SINAMICS V20 1.5kW (230V Single Phase)', 'Variable Frequency Drives', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3RW4027-1BB14', 'Siemens SIRIUS Soft Starter 3RW40 (12A, 400V)', 'Motor Control & Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '5ST3010', 'Siemens SENTRON Residual Current Device (RCD) 2P 25A 30mA', 'Circuit Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '7KM2112-0BA00-3AA0', 'Siemens SENTRON PAC3200 Power Monitoring Device', 'Circuit Protection', ARRAY['all_components_categorized.xlsx']),
  ('Siemens', '3UG4616-1CR20', 'Siemens Current Monitoring Relay 3UG4616 (3-phase)', 'Relays & Monitoring', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PD30CTBR20BPM5IO', 'Diffuse-reflective Photoelectric Sensor with Adjustable Background Suppression', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'A82-20100', 'AC current transducer, input range up to 100 A AC, 4-20 mA DC analogue output, powered by loop voltage, wall mounting', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'B4X-PIR90-U', '90 Degrees Angle for Presence and Movement Detection, 44X44', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'BSD-PIR90-U', '90 Degrees Angle for Presence and Movement Detection, Wall Mounting', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'BTM-T10-RSE', 'High Definition 10 Resistive Colour Touchscreen, 1 Ethernet, 1 Serial, 1 USB', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'BTM-T15-PLUS', 'High Definition 15.6 Capacitive Colour Touchscreen, 3 Ethernet, 1 Serial, 2 USB', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'CA12CAF04BPA2IO', 'Capacitive Proximity Sensor, Flush mountable, Sensing Range 4mm, Adjustable 0.5-4mm, Power Supply 10-40VDC, NPN/PNP Output, N.O./N.C., IO-Link, Cable PVC, Housing M12 x 78mm, 4th Gen. Tripleshield, Improved EMC performances, IP67 IP68', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'CA12CAF04BPM1IO', 'Capacitive Proximity Sensor, Flush mountable, Sensing Range 4mm, Adjustable 0.5-4mm, Power Supply 10-40VDC, NPN/PNP Output, N.O./N.C., IO-Link, M12 4-PIN plug, Housing M12 x 80mm, 4th Gen. Tripleshield, Improved EMC performances, IP67 IP68', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'CA18EAF08BPM1IO', 'Capacitive Proximity Sensor, Flush mountable, Sensing Range 8mm, Adjustable 2-10mm, Supply 10-40VDC, NPN/PNP Output, N.O./N.C., IO-Link, Connector M12, Housing AISI316L M18 x 70mm, 4th Generation Tripleshield, Improved EMC performances, ECOLAB, IP67 IP69K', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'CTD1X1005AXXX', 'Solid core Current transformer 100A/5A', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DAA01CM24', 'Timer Delay on Operate, DIN rail mount, 22,5x80x99,5mm Euronorm housing, selectable time ranges 0,1s - 100h, Supply voltage 24-240Vac and 24Vdc, Screw terminals connection, 8A SPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DAA01DM24', 'Timer Delay on Operate, DIN rail mount, 22,5x80x99,5mm Euronorm housing, selectable time ranges 0,1s - 100h, Supply voltage 24-240Vac and 24Vdc, Screw terminals connection, 8A DPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DAA51CM24', 'Delay on operate timer, time range 0.1 s - 100 h, automatic start, supply voltage 24 V DC and 24-240 V AC, SPDT relay output, 17.5 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DAA71DM24', 'Timer Delay on Operate, DIN rail mount, 35,5x81x67,2 mm housing, selectable time ranges 0,1s - 100h, Supply voltage 24-240Vac and 24Vdc, Screw terminals connection, 5A DPDT relay outpu', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DAC01CM24', 'Timer Star-Delta control, DIN rail mount, 22,5x80x99,5mm Euronorm housing, selectable time ranges 0,1s - 10m, Supply voltage 24-240Vac/Vdc, Screw terminals connection, 8A SPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DAC01CM40', 'Timer Star-Delta control, DIN rail mount, 22,5x80x99,5mm Euronorm housing, selectable time ranges 0,1s - 10m, Supply voltage 380-415Vac, Screw terminals connection, 8A SPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DAC51CM24', 'Star-Delta timer, time range 0.1-600 s , automatic start, supply voltage 24-240 V AC/DC, SPDT relay output, 17.5 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DBB01CM24', 'Timer True delay on release, DIN rail mount, 22,5x80x99,5mm Euronorm housing, selectable time ranges 0,1s - 10m, Supply voltage 24-240Vac/Vdc, Screw terminals connection, 8A SPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DBB01DM24', 'Timer True delay on release, DIN rail mount, 22,5x80x99,5mm Euronorm housing, selectable time ranges 0,1s - 10m, Supply voltage 24-240Vac/Vdc, Screw terminals connection, 8A DPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DBB02CM24', 'Timer True delay on release, built-in battery, DIN rail mount, 22,5x80x99,5mm Euronorm housing, selectable time ranges 60s - 10h, Supply voltage 24-240Vac/Vdc, Screw terminals connection, 8A SPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DBB51CM2410M', 'Timer True delay on release, DIN rail mount, 17,5x81x67,2mm housing, adjustable time settings 60s - 600s, Supply voltage 24-240Vac and 24Vdc, Screw terminals connection, 5A SPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DBB51CM2410S', 'Timer True delay on release, DIN rail mount, 17,5x81x67,2mm housing, adjustable time settings 1s - 10s, Supply voltage 24-240Vac and 24Vdc, Screw terminals connection, 5A SPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DCB51CM24', 'Asymmetrical recycler timer, time range 0.1 s - 100 h, automatic start, supply voltage 24 V DC and 24-240 V AC, SPDT relay output, 17.5 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DLA71DB232P', 'Pump alternating relay for 2 pumps, 2 SPST relay outputs, 35 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DLA71DB482P', 'Pump alternating relay for 2 pumps, 2 SPST relay outputs, 35 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DPB01CM48', '3-phase monitoring relay for phase loss, sequence, over or undervoltage, nominal range 380-480 V AC, delay on alarm 0.1-30 s, SPDT relay output, regenerated voltage detection, 22.5 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DPC01DM44', '3-phase monitoring relay for phase loss, sequence, asymmetry, tolerance, over and undervoltage, nominal range 208-690 V AC, delay on alarm 0.1-30 s, 2 SPDT relay outputs, 45 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DTA02C230', 'Thermistor relay, measuring through PTC, test and reset function, 1 SPDT relay output, 22.5 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DTA04DM24', 'Thermistor relay, measuring through up to 6 PTCs in series, local and remote test and reset function, 2 SPST relay outputs, 22.5 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'DWB01CM2310A', '3-phase power factor monitoring relay, measuring range up to 5A, 10A or with MI current transformers, 1 SPDT relay output, 45 mm DIN-rail housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'EBSSM2310M', 'Mini Interval Timer with adjustable time setting, 1-10m time range, screw connections', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'EBSSM2310MF', 'Mini Interval Timer with adjustable time setting, 1-10m time range, fast-on connections', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'EBSSM2310S', 'Mini Interval Timer with adjustable time setting, 0,5-10s time range, screw connections', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'EBSSM2310SF', 'Mini Interval Timer with adjustable time setting, 0,5-10s time range, fast-on connections', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'ECSSM23A10MF', 'Mini Symmetrical Recycler Timer with adjustable time setting, 1-10m time range, fast-on connections', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'ECSSM23B10S', 'Mini Symmetrical Recycler Timer with adjustable time setting, 0,5-10s time range, screw connections', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'EM21072DAV53XOSX', 'Three-phase Energy analyzer, 160 to 240 V L-N, 277 to 415 V L-L, 5 (6) A, RS485 Modbus RTU Pulse output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'EM24DINAV23XW1IPFA', 'Three-phase MID Energy analyzer, 133 to 230 V L-N, 230 to 400 V L-L, 10 (65) A, Wireless M-Bus, internal antenna', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'G21104401', '4-Channel Transmitter + 1 Channel Receiver Dupline Module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'G32101161', '1 Channel Analink Transmitter for 4-20 mA', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'G34205501230', '8 Channel 230 V AC External Powered Transmitter for Digital Inputs', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'G34205501800', '8 Channel 24 V DC External Powered Transmitter for Digital Inputs', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'G34296470230', '4 Channel Isolated Analog Inputs, Configurable 0-20 mA, 4-20 mA Or 0-10 V DC', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'G34296470800', '4 Channel Isolated Analog Inputs, Configurable 0-20 mA, 4-20 mA Or 0-10 V DC', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'G38000015800', 'Controller and Modbus Interface Controller which Works As A Slave In Networks', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'GH34404412', 'I/O Module for Irrigation Valve Control. DIN Housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'IBS04SF15M5IO', 'Inductive proximity sensor, D4 Stainless steel, M8 plug, Sn 1.5mm, Flush mount, Short body, NPN/PNP/Push-pull, NO/NC, Supply voltage 10-30Vdc, Max output current 100 mA, Max switching frequency 4.5 kHz, Operating temperature -25C - +70C, IP67, IO-Link', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'ICB12S30F04POM1', 'Inductive proximity sensor, M12 Nickel-Plated Brass, M12 plug, Sn 4mm, Flush mount, Short body, PNP NO output, Supply voltage 10-36Vdc, Max output current 200 mA, Max switching frequency 2 kHz, Operating temperature -25C - +70C, IP67', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'MC3', 'Proximity magnetic sensors, Rectangular housing, 0.5m cable, Reed NC output, Max swiching voltage 500 Vac, Max swiching current 500mA, Max switching power 10VA, Max switching distance 30mm, Operating temperature -25C - +75C, IP67.', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PA18CAB20PAM1SA', 'Diffuse-reflective Photoelectric Sensor with Background Suppression', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PAA01CM24', 'Timer Delay on Operate, Plug-in Socket mount, 36x80x94mm Euronorm housing, selectable time ranges 0,1s - 100h, Supply voltage 24-240Vac and 24Vdc, 8A SPDT relay output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PAM03DB1RAU24', 'Amplifier for 3 Through Beam sensors, Range up to: 50000mm, Adjustable Sensitivity, Diagnostic Functions, Alignment help, Power Supply : 24-42 VAC/DC, SPDT RELAY outputs, NO/NC, DIN-rail Spring terminals, UL508, UL325, Test input', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PCB01DM24', 'Asymmetrical recycler timer, time range 0.1 s - 100 h, automatic start, supply voltage 24-240 V AC/DC, 2 SPDT relay outputs, 36 mm plug-in housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PE12CNT15PO', 'Through-beam Photoelectric Receiver, Range 15m, Infrared modulated light 880nm', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PH18CNB20PAM1SA', 'Diffuse-reflective Photoelectric Sensor with Background Suppression, adjustable sensitivity', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PMD8RG', 'Diffuse-reflective Photoelectric Sensor, range 800 mm, Infrared modulated light 880nm, Power Supply 10.8-264VDC&21.6-264VAC, Relay SPDT, NO+NC, Terminals, IP67. PG13.5', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PS21L-AS11PR-T00', 'Electromechanical limit switch; metal roller plunger; 30x30mm plastic housing; 1NO+1NC snap-on contacts; M16 cable gland; IP65; -25 - +70C operating temperature', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'PS21L-BS11RH-T00', 'Electromechanical limit switch; plastic roller lever on metal plunger; left displacement; 30x30mm plastic housing; 1NO+1NC snap-on contacts; PG11 cable gland; IP65; -25 - +70C operating temperature', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RCP11003230VAC', 'Industrial Electromechanical Relays series, 10A 250VAC/30VDC, 11 poles Undecal, 3PDT (3 Change Over contacts), Coil voltage 230VAC', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RCP1100324VAC', 'Industrial Electromechanical Relays series, 10A 250VAC/30VDC, 11 poles Undecal, 3PDT (3 Change Over contacts), Coil voltage 24VAC', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RGC1A60D30KKE', '1-pole DIN-rail mount SSR, E-layout, Zero-cross switching, Operating voltage (Ue): 42 - 660 Vac (1200 Vp), Rated current (Ie): 30 Aac, Control voltage (Uc): 4 - 32 Vdc, Built-in overvoltage protection', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RMIA45230AC', 'Industrial Electromechanical Relays series, 5A 250VAC/30VDC, 14 poles, 4PDT (4 Change Over contacts), Coil voltage 230VAC', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RMIA4524DC', 'Industrial Electromechanical Relays series, 5A 250VAC/30VDC, 14 poles, 4PDT (4 Change Over contacts), Coil voltage 24VDC', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RSLSA230D020IG1', '1-pole SSR + Socket (SPR), AC zero-cross switching, Operating voltage (Ue): 24 - 280 Vac, Rated current (Ie): 2.0 Aac, Control voltage (Uc): 15 - 24 Vdc, Packed x10', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RSLSD048M001IN1', '1-pole SSR + Socket (SRW), DC switching, Operating voltage (Ue): 1 - 48 Vdc, Rated current (Ie): 100 mAdc, Control voltage (Uc): 6 - 12 Vdc, Packed x10', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RVLFA110075A', '1 phase frequency drive for induction motors, Operating voltage (Ue): 100 - 120 Vac, Output power: 0.75 kW, Panel mount, Modbus RTU, IP20, EMC filter, Frame Size A', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RVLFA320040A', '3 phase frequency drive for induction motors, Operating voltage (Ue): 200 - 240 Vac, Output power: 0.4 kW, Panel mount, Modbus RTU, IP20, EMC filter, Frame size A', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'RVLFB120220FA', '1 phase frequency drive for induction motors, Operating voltage (Ue): 200 - 240 Vac, Output power: 2.2 kW, Panel mount, Modbus RTU, IP20, EMC filter, Frame size B', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'S142ARNN024', 'Amplifier for Through Beam sensors, Range up to: 50000mm, Adjustable Sensitivity, Disgnostic Functions, Alignment help, Power Supply : 24 Vac, SPDT relay + NPN output, 11 pole Plug Connection, UL508, UL325, CSA, Alarm Output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SB2REP230', 'Smart-Dupline repeater and isolator module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SD2DUG24', 'Dupline bus generator module in 2-DIN housing, supplied 24 V DC', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SH2DSP24', 'USB Dongle Connection Module for Data Modem', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SH2MCG24', 'Smart Dupline bus generator module in 2-DIN housing, supplied 24 V DC', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SH2RE16A4', 'Smart Dupline relay output module in 2-DIN housing, supplied by the Dupline bus, 16 A load connectable to each output', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SH2RE1A424', 'Smart-Dupline Output Module, 4 Relays, Up To 5 A', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SHSUTD', 'Smart-Dupline Module, Temperature Sensor with Display for Wall Mounting', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SHSUTHD', 'Smart-Dupline Module, Temperature and Humidity Sensors with Display for Wall Mounting', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPDL241201', 'Switching Power Supply, AC/DC, 120W, 24V, 5A, Screw Terminals, IP20, DIN-Rail Mounting, Over-load, Over-voltage, Short-circuit and Over-temperature Protections, metal housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPDL24601', 'Switching Power Supply, AC/DC, 60W, 24V, Screw Terminals, IP20, DIN-Rail Mounting, Over-load, Over-voltage and Short-circuit Protections, plastic housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPM5BC2460', 'Low Profile Switching Power Supply Battery Charger, 1-phase, 24Vdc, 68W, DIN Rail Mounting, 5-DIN module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPM5-BOTPLAT', 'Low Profile Switching Power Supply, 1-phase, 5Vdc, 7,5W, DIN Rail Mounting, 5-DIN module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPMA05301SCC', 'Switching Power Supply, Low Profile, AC/DC, 30W, 5V, 6A, Special Conformal Coating, Screw Terminals, IP20, DIN-Rail Mounting, Over-load, Over-voltage and Short-circuit Protections, 52x91x63mm plastic housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPMA12151', 'Switching Power Supply, Low Profile, AC/DC, 15W, 12V, 1.25A, Screw Terminals, IP20, DIN-Rail Mounting, Over-load, Over-voltage and Short-circuit Protections, 18x91x63mm plastic housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPMA12301', 'Switching Power Supply, Low Profile, AC/DC, 25.2W, 12V, 2.1A, Screw Terminals, IP20, DIN-Rail Mounting, Over-load, Over-voltage and Short-circuit Protections, 52x91x63mm plastic housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPMA12601', 'Switching Power Supply, Low Profile, AC/DC, 54W, 12V, 4.5A, Screw Terminals, IP20, DIN-Rail Mounting, Over-load, Over-voltage and Short-circuit Protections, 52x91x63mm plastic housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPUBC12120', 'Switching Power Supply, UPS and Battery Charger, AC, 120W, 12V, Screw Terminals, IP20, DIN-Rail Mounting, Over-load, Over-voltage, Short-circuit, Over-temperature and Battery Charging Protections, 65x115x135mm metallic housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPUBC24120', 'Switching Power Supply, UPS and Battery Charger, AC, 120W, 24V, Screw Terminals, IP20, DIN-Rail Mounting, Over-load, Over-voltage, Short-circuit, Over-temperature and Battery Charging Protections, 65x115x135mm metallic housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'SPUC24720', 'Switching Power Supply, UPS Controller, DC, 720W, 24V, Screw Terminals, IP20, DIN-Rail Mounting, Battery Charging Protections, 54x90x115mm metallic housing', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'UA18ASD08APM1IO', 'Ultrasonic Sensor, Diffuse Reflective, M18 NPB housing, M12 Connector, Sn 80-800mm, Analogue Output 0-10V, 4-20mA, 0-20mA, Push-Pull, NPN, PNP, Supply Voltage 18-30VDC, Operating Temperature -25-+70C, Switching Frequency 5Hz, IP67, Teach-by wire, IO-Link', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'UA30ASD30APM1IO', 'Ultrasonic Sensor, Diffuse Reflective, M30 NPB housing, M12 Connector, Sn 300-3000mm, Analogue Output 0-10V, 4-20mA, 0-20mA, Push-Pull, NPN, PNP,Supply Voltage 18-30VDC, Operating Temperature -25-+70C, Switching Frequency 3Hz, IP67, Teach-by wire, IO-Link', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'UWP30RSEXXX', 'Monitoring datalogger, gateway and controller with embedded web server and building automation functions', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'UWP30RSEXXXSE', 'Monitoring datalogger, gateway and controller with embedded web server and building automation functions', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'UWP40RSEXXX', 'Datalogger/Gateway/Controller with Web-Server, Building Automation functions', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'UWP40RSEXXXSE', 'Datalogger / Gateway / Controller with Web-Server, Building Automationfunctions', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'UWPAM1US1L1X', 'Wireless endpoint Gateway; Connected To Meters Via RS485; High-Performance Antenna', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'VP01E', 'Sensor for liquid level detection. High chemical resistance', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'VP01EP', 'Sensor for liquid level detection. High chemical resistance.', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'VP02E', 'Sensor for liquid level detection. High chemical resistance.', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'VPA1MPA', 'Sensor for liquid level detection. High chemical resistance. Infrared light. Stainless steel AISI 303 housing.', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Carlo Gavazzi', 'ZMI4NA', 'Sockets for RMIA Industrial Electromechanical Relays, 14 poles, 4PDT (4 Change Over contacts), 10A, Screw terminals, Terminals on 2 levels, with included Plastic Clamp and ID Tag', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '404017', 'AK 4 - Connection terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1029994', 'RSCWE 6-3/4SL - Test terminal strip', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1032919', 'ELR 1-SC-24DC/600AC-20 - Solid-state contactor', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1032921', 'ELR 1-SC-24DC/600AC-30 - Solid-state contactor', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1046666', 'BTP 2070W - Touch panel', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1046667', 'BTP 2102W - Touch panel', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1065635', 'QUINT4-CAP/24DC/20/16KJ/USB - DC UPS with integrated capacity', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1084335', 'SCK-C-MODBUS-10PCS - PV string monitoring module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1136513', 'ECM-UC-100A-UI - Current measuring transducer', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1136811', 'QUINT-HP-UPS/230AC/1.5KVA/PT - Uninterruptible power supply', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1136813', 'QUINT-HP-UPS/120AC/2.5KVA/PT - Uninterruptible power supply', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1274117', 'UPS-BAT/PB/24DC/4AH - Battery module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1274119', 'UPS-BAT/PB/24DC/12AH - Battery module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1274520', 'UPS-BAT/PB/24DC/1.2AH - Battery module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1319320', 'EXTENDER 2010 ETH COAX-G - Ethernet extender', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1319569', 'PLD E 409 W 350 - LED enclosure light', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1343106', 'XT 2,5 - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1354641', 'UPS-BAT/PB/24DC/40AH - Battery module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1359604', 'TRIO3-UPS/1AC/24DC/10/485-USB - Uninterruptible power supply', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1376798', 'VL3 PPC - Panel PC', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1541303', 'ILC 2250 BI - Controller', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1694094', 'PLD E 708 W 400 MS/F - LED enclosure light', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1698172', 'ECM-UC-100A-UI-REL - Current measuring transducer', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1721731', 'MKKDS 3/ 3-5,08 - PCB terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1729209', 'MKDSN 1,5/10-5,08 - PCB terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1731831', 'MKKDSNH 1,5/ 3-5,08 - PCB terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1733606', 'SMKDSP 1,5/ 5-5,08 - PCB terminal bloc', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1761792', 'CMU-DC-20A-S/UDM - Current monitoring', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1791341', 'CBL-SC-230UC/20/32A - Installation contactor', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1791346', 'CBL-SC-230UC/40/32A - Installation contactor', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1791371', 'CBL-SC-230UC/40/40A - Installation contactor', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1812693', 'ELR 3-SC-24DC/600AC-20 - Solid-state contactor', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1869282', 'SMKDSN 1,5/ 9-5,08 - PCB terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '1886438', 'CATAN C1 - Controller', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2100014', 'AI-TWIN 2X 0,75 - 12 WH - Ferrule', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2277019', 'PACT MCR-V1-21-44- 50-5A-1 - Current transformer', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2277598', 'PACT MCR-RA - DIN rail adapter', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2277925', 'PACT MCR-V2-6015- 85- 600-5A-1 - Current transformer', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2308043', 'MCR-SL-CUC-300-I - Universal current transduce', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2313452', 'FL COMSERVER UNI 232/422/485 - Interface converters', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2320254', 'QUINT-UPS/ 24DC/ 24DC/ 5/1.3AH - Uninterruptible power supply', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2320267', 'QUINT-UPS/ 24DC/ 24DC/10/3.4AH - Uninterruptible power supply', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2320283', 'QUINT4-UPS/1AC/1AC/1KVA - Uninterruptible power supply', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2320380', 'UPS-CAP/24DC/20A/20KJ - Energy storage', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2320393', 'QUINT-BUFFER/24DC/24DC/40 - Buffer module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2688035', 'AXL F DI32/1 1F - Digital module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2688064', 'AXL F AI8 1F - Analog module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2702258', 'TC EXTENDER PT-IQ-2S - Surge protection plug', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2702409', 'TC EXTENDER 2001 ETH-2S - Ethernet extender', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2702764', 'GW MODBUS TCP/RTU 1E/1DB9 - Interface converters', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2810612', 'MACX MCR-SL-CAC- 5-I - Current measuring transducer', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2810625', 'MACX MCR-SL-CAC- 5-I-UP - Current measuring transducer', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2813486', 'MCR-SL-S-100-I-LP - Current measuring transducer', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2901528', 'EM-MODBUS-GATEWAY-IFS - Data interface', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2901988', 'EM-ETH-GATEWAY-IFS - Data interface', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2905908', 'TRIO-UPS-2G/1AC/1AC/120V/750VA - Uninterruptible power supply', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2906242', 'MACX MCR-VDC - Voltage measuring transducers', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2906244', 'MACX MCR-VAC-PT - Voltage measuring transducers', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '2907913', 'QUINT4-BUFFER/24DC/20 - Buffer module', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3004362', 'UK 5 N - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3005947', 'FBS 2-10 - Plug-in bridge', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3009118', 'UKH 50 - High-current terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3010013', 'UKH 95 - High-current terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3024481', 'ATP-ST 6 - Partition plate', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3030271', 'FBS 10-6 - Plug-in bridge', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3030365', 'FBS 20-6 - Plug-in bridge', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3030747', 'ATP-STTB 4 - Partition plate', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3031212', 'ST 2,5 - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3031306', 'ST 2,5-QUATTRO - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3033126', 'STU 35/ 4X10 - Potential collective terminal', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3033210', 'STU 35/ 4X10 BU - Potential collective terminal', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3036149', 'ST 16 - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3047167', 'ATP-UT - Partition plate', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3050044', 'QTCU 1,5-TWIN - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3050138', 'QTCS 1,5 - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3050426', 'QTTCBS 1,5 OG - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3069222', 'FTP 3+1 - Test plug', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3069259', 'FTPC 3+1 - Test plug', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3069930', 'FTPC-3/4S - Test plug', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3200195', 'AI 1,5 -10 BK - Ferrule', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3200519', 'AI 0,75- 8 GY - Ferrule', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3200548', 'AI 6 -12 YE - Ferrule', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3200564', 'AI 16 -12 BU - Ferrule', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3200810', 'AI-TWIN 2X 1 - 8 RD - Ferrule', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3200933', 'AI-TWIN 2X 0,5 - 8 WH - Ferrule', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3200962', 'AI 2,5 -12 BU - Ferrule', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3203066', 'AI 0,34- 8 TQ - Ferrule', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3209515', 'PTU 2,5-TWIN - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3209519', 'PTU 2,5 - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3210567', 'PTTB 2,5 - Double-level terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3211859', 'PTU 4-TWIN - Feed-through terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3213140', 'UKH 70 - High-current terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3213142', 'UKH 70/4X10 - Potential collective terminal', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3213960', 'PTI 2,5-PE/L/TG - Installation protective conductor terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3213961', 'PTI 2,5-L/TG - Installation level terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3240025', 'C-RCI 2,5/M6 - Ring cable lug', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3240033', 'C-FCI 1,5/M3,5 - Fork-type cable lug', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3240083', 'C-RC 6/M4 DIN - Ring cable lug', 'Uncategorized', ARRAY['all_components_categorized.xlsx']),
  ('Phoenix Contact', '3244601', 'UKH 70 BU - High-current terminal block', 'Uncategorized', ARRAY['all_components_categorized.xlsx'])
ON CONFLICT (brand, part_number) DO NOTHING;

-- =====================================================
-- DONE — verify with:
--   SELECT brand, COUNT(*) FROM public.products GROUP BY brand;
-- =====================================================
