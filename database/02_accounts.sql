-- ============================================================
-- АСУ ТП «Автоматика» — демонстрационные LOGIN-роли
-- Версия для запуска через pgAdmin Query Tool
--
-- Запускать после 01_schema.sql в базе asu_tp_db
-- от пользователя postgres (или пользователя с правом CREATEROLE).
-- ============================================================

SET client_encoding = 'UTF8';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_unprivileged') THEN
        CREATE ROLE user_unprivileged LOGIN PASSWORD 'unpriv123';
    ELSE
        ALTER ROLE user_unprivileged WITH LOGIN PASSWORD 'unpriv123';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_operator') THEN
        CREATE ROLE user_operator LOGIN PASSWORD 'pass123';
    ELSE
        ALTER ROLE user_operator WITH LOGIN PASSWORD 'pass123';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_privileged') THEN
        CREATE ROLE user_privileged LOGIN PASSWORD 'priv123';
    ELSE
        ALTER ROLE user_privileged WITH LOGIN PASSWORD 'priv123';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_engineer') THEN
        CREATE ROLE user_engineer LOGIN PASSWORD 'pass123';
    ELSE
        ALTER ROLE user_engineer WITH LOGIN PASSWORD 'pass123';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_admin') THEN
        CREATE ROLE user_admin LOGIN PASSWORD 'admin123';
    ELSE
        ALTER ROLE user_admin WITH LOGIN PASSWORD 'admin123';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_ib_admin') THEN
        CREATE ROLE user_ib_admin LOGIN PASSWORD 'ib123';
    ELSE
        ALTER ROLE user_ib_admin WITH LOGIN PASSWORD 'ib123';
    END IF;
END $$;

GRANT app_unprivileged TO user_unprivileged;
GRANT app_operator     TO user_operator;
GRANT app_privileged   TO user_privileged;
GRANT app_engineer     TO user_engineer;
GRANT app_admin        TO user_admin;
GRANT app_ib_admin     TO user_ib_admin;

UPDATE asu_schema.users
SET is_active = TRUE,
    updated_at = CURRENT_TIMESTAMP
WHERE login IN ('unprivileged', 'operator', 'privileged', 'engineer', 'admin', 'ib_admin');

SELECT
    rolname AS login_role,
    rolcanlogin AS can_login
FROM pg_roles
WHERE rolname IN (
    'user_unprivileged',
    'user_operator',
    'user_privileged',
    'user_engineer',
    'user_admin',
    'user_ib_admin'
)
ORDER BY rolname;
