-- ============================================================
-- АСУ ТП «Автоматика» — схема БД
-- PostgreSQL 9.6 / Astra Linux «Орел» 1.7.5
-- ============================================================

SET client_encoding = 'UTF8';

-- ============================================================
-- 0. Групповые роли PostgreSQL
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_unprivileged') THEN
        CREATE ROLE app_unprivileged NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_operator') THEN
        CREATE ROLE app_operator NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_privileged') THEN
        CREATE ROLE app_privileged NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_engineer') THEN
        CREATE ROLE app_engineer NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_admin') THEN
        CREATE ROLE app_admin NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_ib_admin') THEN
        CREATE ROLE app_ib_admin NOLOGIN;
    END IF;
END $$;

GRANT CONNECT ON DATABASE asu_tp_db TO
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

-- ============================================================
-- 1. Чистое создание схемы
-- ============================================================

DROP SCHEMA IF EXISTS asu_schema CASCADE;
CREATE SCHEMA asu_schema;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SET search_path TO asu_schema, public;

-- ============================================================
-- 2. Базовые таблицы
-- ============================================================

CREATE TABLE positions (
    position_id SERIAL PRIMARY KEY,
    position_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE roles (
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    can_read BOOLEAN NOT NULL DEFAULT FALSE,
    can_write BOOLEAN NOT NULL DEFAULT FALSE,
    can_execute BOOLEAN NOT NULL DEFAULT FALSE,
    can_manage_users BOOLEAN NOT NULL DEFAULT FALSE,
    can_audit BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE permissions (
    permission_id SERIAL PRIMARY KEY,
    action_name VARCHAR(50) NOT NULL,
    object_name VARCHAR(50) NOT NULL,
    permission_code VARCHAR(120) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE role_permissions (
    role_id INTEGER NOT NULL REFERENCES roles(role_id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(permission_id) ON DELETE CASCADE,
    is_allowed BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    login VARCHAR(50) UNIQUE NOT NULL,
    position_id INTEGER REFERENCES positions(position_id),
    role_id INTEGER REFERENCES roles(role_id),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP,
    CONSTRAINT chk_users_login_format CHECK (login ~ '^[a-z][a-z0-9_]{2,30}$')
);

CREATE TABLE event_types (
    event_type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) UNIQUE NOT NULL,
    severity_level INTEGER NOT NULL DEFAULT 1 CHECK (severity_level BETWEEN 1 AND 5)
);

CREATE TABLE action_types (
    action_type_id SERIAL PRIMARY KEY,
    action_name VARCHAR(100) UNIQUE NOT NULL,
    default_description TEXT
);

CREATE TABLE control_objects (
    object_id SERIAL PRIMARY KEY,
    object_name VARCHAR(120) NOT NULL,
    object_type VARCHAR(50) NOT NULL,
    location VARCHAR(120) NOT NULL,
    unit VARCHAR(20),
    min_limit REAL,
    max_limit REAL,
    current_value REAL NOT NULL DEFAULT 0,
    last_update TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_commercial_secret BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_control_object_limits
        CHECK (min_limit IS NULL OR max_limit IS NULL OR min_limit <= max_limit)
);

CREATE TABLE access_log (
    log_id BIGSERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    db_user TEXT NOT NULL DEFAULT session_user,
    event_type_id INTEGER REFERENCES event_types(event_type_id),
    action_type_id INTEGER REFERENCES action_types(action_type_id),
    object_id INTEGER REFERENCES control_objects(object_id) ON DELETE SET NULL,
    old_value REAL,
    new_value REAL,
    action_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description TEXT,
    ip_address INET,
    success BOOLEAN NOT NULL DEFAULT TRUE,
    error_message TEXT
);


CREATE TABLE alarm_log (
    alarm_id BIGSERIAL PRIMARY KEY,
    object_id INTEGER REFERENCES control_objects(object_id) ON DELETE SET NULL,
    event_type_id INTEGER REFERENCES event_types(event_type_id),
    alarm_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'CONFIRMED', 'CLOSED')),
    confirmed_by INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    confirmed_at TIMESTAMP
);


-- Индексы
CREATE INDEX idx_users_login ON users(login);
CREATE INDEX idx_users_role ON users(role_id);
CREATE INDEX idx_access_log_user ON access_log(user_id);
CREATE INDEX idx_access_log_date ON access_log(action_date);
CREATE INDEX idx_access_log_success ON access_log(success);
CREATE INDEX idx_control_objects_secret ON control_objects(is_commercial_secret);
CREATE INDEX idx_alarm_status_time ON alarm_log(status, alarm_time);

-- ============================================================
-- 3. Справочные данные и тестовое наполнение
-- ============================================================

INSERT INTO positions (position_name, description) VALUES
    ('Оператор ТП', 'Оператор технологического процесса формования и тепловлажностной обработки ЖБК'),
    ('Инженер АСУ ТП', 'Инженер, отвечающий за настройку технологических параметров АСУ ТП'),
    ('Администратор ИС', 'Администратор информационной системы'),
    ('Администратор ИБ', 'Администратор информационной безопасности'),
    ('Привилегированный пользователь', 'Пользователь с расширенными технологическими правами'),
    ('Непривилегированный пользователь', 'Пользователь с минимальными правами просмотра')
ON CONFLICT (position_name) DO NOTHING;

INSERT INTO roles (role_name, description, can_read, can_write, can_execute, can_manage_users, can_audit) VALUES
    ('Непривилегированный', 'Просмотр открытых технологических параметров', TRUE, FALSE, FALSE, FALSE, FALSE),
    ('Оператор', 'Просмотр параметров и аварий, подтверждение аварийных сообщений', TRUE, FALSE, TRUE, FALSE, FALSE),
    ('Привилегированный', 'Расширенный доступ к технологическим параметрам и изменение разрешенных значений', TRUE, TRUE, TRUE, FALSE, FALSE),
    ('Инженер', 'Настройка и изменение технологических параметров, просмотр журнала изменений', TRUE, TRUE, TRUE, FALSE, FALSE),
    ('Администратор ИС', 'Управление пользователями и служебными объектами ИС', TRUE, TRUE, TRUE, TRUE, FALSE),
    ('Администратор ИБ', 'Аудит, контроль нарушений, просмотр журналов операций и событий безопасности', TRUE, FALSE, FALSE, FALSE, TRUE)
ON CONFLICT (role_name) DO NOTHING;

INSERT INTO permissions (action_name, object_name, permission_code, description) VALUES
    ('READ', 'PUBLIC_PARAMS', 'READ:PUBLIC_PARAMS', 'Просмотр общедоступных технологических параметров'),
    ('READ', 'ALL_PARAMS', 'READ:ALL_PARAMS', 'Просмотр всех технологических параметров'),
    ('WRITE', 'PARAMETER', 'WRITE:PARAMETER', 'Изменение технологического параметра'),
    ('READ', 'ALARMS', 'READ:ALARMS', 'Просмотр аварийных сообщений'),
    ('CONFIRM', 'ALARM', 'CONFIRM:ALARM', 'Подтверждение аварийного сообщения'),
    ('READ', 'CHANGE_LOG', 'READ:CHANGE_LOG', 'Просмотр журнала изменений параметров'),
    ('READ', 'ACCESS_LOG', 'READ:ACCESS_LOG', 'Просмотр полного журнала операций'),
    ('READ', 'USERS', 'READ:USERS', 'Просмотр списка пользователей'),
    ('MANAGE', 'USERS', 'MANAGE:USERS', 'Добавление и блокировка пользователей'),
    ('READ', 'RIGHTS_MATRIX', 'READ:RIGHTS_MATRIX', 'Просмотр матрицы прав')
ON CONFLICT (permission_code) DO NOTHING;

-- Права по ролям
INSERT INTO role_permissions (role_id, permission_id, is_allowed)
SELECT r.role_id, p.permission_id, TRUE
FROM roles r
JOIN permissions p ON p.permission_code IN ('READ:PUBLIC_PARAMS')
WHERE r.role_name IN (
    'Непривилегированный',
    'Оператор',
    'Привилегированный',
    'Инженер',
    'Администратор ИС',
    'Администратор ИБ'
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id, is_allowed)
SELECT r.role_id, p.permission_id, TRUE
FROM roles r
JOIN permissions p ON p.permission_code IN ('READ:ALARMS')
WHERE r.role_name IN (
    'Оператор',
    'Привилегированный',
    'Инженер',
    'Администратор ИС',
    'Администратор ИБ'
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id, is_allowed)
SELECT r.role_id, p.permission_id, TRUE
FROM roles r
JOIN permissions p ON p.permission_code IN (
    'READ:ALL_PARAMS',
    'WRITE:PARAMETER',
    'READ:CHANGE_LOG'
)
WHERE r.role_name IN ('Привилегированный', 'Инженер', 'Администратор ИС')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id, is_allowed)
SELECT r.role_id, p.permission_id, TRUE
FROM roles r
JOIN permissions p ON p.permission_code IN ('CONFIRM:ALARM')
WHERE r.role_name IN ('Оператор', 'Привилегированный', 'Инженер', 'Администратор ИС')
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id, is_allowed)
SELECT r.role_id, p.permission_id, TRUE
FROM roles r
JOIN permissions p ON p.permission_code IN (
    'READ:USERS',
    'MANAGE:USERS',
    'READ:RIGHTS_MATRIX'
)
WHERE r.role_name = 'Администратор ИС'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id, is_allowed)
SELECT r.role_id, p.permission_id, TRUE
FROM roles r
JOIN permissions p ON p.permission_code IN (
    'READ:ACCESS_LOG',
    'READ:CHANGE_LOG',
    'READ:USERS',
    'READ:RIGHTS_MATRIX'
)
WHERE r.role_name = 'Администратор ИБ'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO event_types (type_name, severity_level) VALUES
    ('Информационное сообщение', 1),
    ('Предупреждение', 2),
    ('Отклонение параметра', 3),
    ('Авария', 4),
    ('Критическая авария', 5)
ON CONFLICT (type_name) DO NOTHING;

INSERT INTO action_types (action_name, default_description) VALUES
    ('LOGIN', 'Вход пользователя в систему'),
    ('LOGOUT', 'Выход пользователя из системы'),
    ('VIEW_OBJECT', 'Просмотр технологических параметров или объектов'),
    ('UPDATE_VALUE', 'Изменение значения технологического параметра'),
    ('CONFIRM_ALARM', 'Подтверждение аварийного сообщения'),
    ('ADD_USER', 'Добавление пользователя'),
    ('BLOCK_USER', 'Блокировка пользователя'),
    ('UNBLOCK_USER', 'Разблокировка пользователя'),
    ('UPDATE_USER', 'Изменение данных пользователя'),
    ('CHANGE_PASSWORD', 'Смена пароля пользователя'),
    ('READ_LOG', 'Просмотр журнала операций'),
    ('POLICY_DENY', 'Отказ политикой безопасности'),
    ('ERROR', 'Служебная ошибка выполнения операции')
ON CONFLICT (action_name) DO NOTHING;

INSERT INTO users (full_name, login, position_id, role_id, is_active) VALUES
    ('Иванов Иван Оператор', 'operator',
        (SELECT position_id FROM positions WHERE position_name = 'Оператор ТП'),
        (SELECT role_id FROM roles WHERE role_name = 'Оператор'), TRUE),
    ('Петров Пётр Инженер', 'engineer',
        (SELECT position_id FROM positions WHERE position_name = 'Инженер АСУ ТП'),
        (SELECT role_id FROM roles WHERE role_name = 'Инженер'), TRUE),
    ('Сидоров Сидор Администратор', 'admin',
        (SELECT position_id FROM positions WHERE position_name = 'Администратор ИС'),
        (SELECT role_id FROM roles WHERE role_name = 'Администратор ИС'), TRUE),
    ('Смирнова Анна Администратор ИБ', 'ib_admin',
        (SELECT position_id FROM positions WHERE position_name = 'Администратор ИБ'),
        (SELECT role_id FROM roles WHERE role_name = 'Администратор ИБ'), TRUE),
    ('Кузнецов Кирилл Привилегированный пользователь', 'privileged',
        (SELECT position_id FROM positions WHERE position_name = 'Привилегированный пользователь'),
        (SELECT role_id FROM roles WHERE role_name = 'Привилегированный'), TRUE),
    ('Николаев Николай Наблюдатель', 'unprivileged',
        (SELECT position_id FROM positions WHERE position_name = 'Непривилегированный пользователь'),
        (SELECT role_id FROM roles WHERE role_name = 'Непривилегированный'), TRUE)
ON CONFLICT (login) DO NOTHING;

-- Технологические объекты предметной области ЖБК
INSERT INTO control_objects (
    object_name, object_type, location, unit,
    min_limit, max_limit, current_value, is_commercial_secret
) VALUES
    ('Температура камеры ТВО-1', 'датчик температуры', 'Цех №2, камера тепловлажностной обработки ТВО-1', '°C', 20, 90, 65, FALSE),
    ('Влажность камеры ТВО-1', 'датчик влажности', 'Цех №2, камера тепловлажностной обработки ТВО-1', '%', 40, 100, 85, FALSE),
    ('Уровень цемента в силосе С-1', 'датчик уровня', 'Бетоносмесительный узел, силос С-1', '%', 5, 100, 72, TRUE),
    ('Масса цемента в дозаторе', 'весовой дозатор', 'Бетоносмесительный узел, дозатор цемента', 'кг', 0, 500, 320, TRUE),
    ('Масса песка в дозаторе', 'весовой дозатор', 'Бетоносмесительный узел, дозатор песка', 'кг', 0, 800, 540, FALSE),
    ('Масса щебня в дозаторе', 'весовой дозатор', 'Бетоносмесительный узел, дозатор щебня', 'кг', 0, 1200, 900, FALSE),
    ('Расход воды в смеситель', 'расходомер', 'Бетоносмесительный узел, линия подачи воды', 'л/мин', 0, 100, 42, TRUE),
    ('Температура бетонной смеси', 'датчик температуры', 'Бетоносмесительный узел, бетоносмеситель БС-1', '°C', 5, 35, 22, FALSE),
    ('Вибрация виброплощадки ВП-1', 'датчик вибрации', 'Цех №1, пост формования, виброплощадка ВП-1', 'мм/с', 0, 10, 5.4, FALSE),
    ('Состояние бетоносмесителя БС-1', 'механизм', 'Бетоносмесительный узел, бетоносмеситель БС-1', NULL, 0, 1, 1, FALSE),
    ('Положение задвижки подачи воды', 'задвижка', 'Бетоносмесительный узел, линия подачи воды', '%', 0, 100, 35, TRUE),
    ('Давление гидросистемы пресса П-1', 'датчик давления', 'Цех №1, прессовая линия П-1', 'МПа', 1, 20, 12, FALSE)
ON CONFLICT DO NOTHING;

-- ============================================================
-- 4. Служебные функции безопасности и аудита
-- ============================================================

CREATE OR REPLACE FUNCTION f_current_app_login()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_login TEXT;
BEGIN
    v_login := session_user;

    IF v_login LIKE 'user_%' THEN
        v_login := substring(v_login FROM 6);
    END IF;

    RETURN v_login;
END;
$$;

CREATE OR REPLACE FUNCTION get_current_user_id()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    SELECT user_id
    INTO v_user_id
    FROM users
    WHERE login = f_current_app_login()
      AND is_active = TRUE;

    RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION asu_schema.log_error(
    p_sql_state TEXT,
    p_error_msg TEXT,
    p_stack TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_event_type_id INTEGER;
    v_action_type_id INTEGER;
BEGIN
    SELECT event_type_id
    INTO v_event_type_id
    FROM event_types
    WHERE type_name = 'Предупреждение';

    SELECT action_type_id
    INTO v_action_type_id
    FROM action_types
    WHERE action_name = 'ERROR';

    INSERT INTO access_log (
        user_id,
        db_user,
        event_type_id,
        action_type_id,
        object_id,
        old_value,
        new_value,
        description,
        ip_address,
        success,
        error_message
    )
    VALUES (
        get_current_user_id(),
        session_user,
        v_event_type_id,
        v_action_type_id,
        NULL,
        NULL,
        NULL,
        'Служебная ошибка выполнения операции',
        inet_client_addr(),
        FALSE,
        COALESCE(p_sql_state, '') || ' ' || COALESCE(p_error_msg, '') ||
            CASE
                WHEN p_stack IS NULL THEN ''
                ELSE E'
' || p_stack
            END
    );
EXCEPTION WHEN OTHERS THEN
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION check_policy(
    p_action TEXT,
    p_object TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_allowed BOOLEAN := FALSE;
BEGIN
    IF session_user = 'postgres' THEN
        RETURN TRUE;
    END IF;

    SELECT COALESCE(rp.is_allowed, FALSE)
    INTO v_allowed
    FROM users u
    JOIN roles r ON r.role_id = u.role_id
    JOIN role_permissions rp ON rp.role_id = r.role_id
    JOIN permissions p ON p.permission_id = rp.permission_id
    WHERE u.login = f_current_app_login()
      AND u.is_active = TRUE
      AND p.permission_code = upper(p_action) || ':' || upper(p_object)
    LIMIT 1;

    RETURN COALESCE(v_allowed, FALSE);
END;
$$;

CREATE OR REPLACE FUNCTION log_access(
    p_action_name TEXT,
    p_event_type_name TEXT DEFAULT 'Информационное сообщение',
    p_object_id INTEGER DEFAULT NULL,
    p_old_value REAL DEFAULT NULL,
    p_new_value REAL DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_success BOOLEAN DEFAULT TRUE,
    p_error_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_user_id INTEGER;
    v_event_type_id INTEGER;
    v_action_type_id INTEGER;
BEGIN
    v_user_id := get_current_user_id();

    SELECT event_type_id
    INTO v_event_type_id
    FROM event_types
    WHERE type_name = COALESCE(p_event_type_name, 'Информационное сообщение');

    SELECT action_type_id
    INTO v_action_type_id
    FROM action_types
    WHERE action_name = p_action_name;

    INSERT INTO access_log (
        user_id,
        db_user,
        event_type_id,
        action_type_id,
        object_id,
        old_value,
        new_value,
        description,
        ip_address,
        success,
        error_message
    )
    VALUES (
        v_user_id,
        session_user,
        v_event_type_id,
        v_action_type_id,
        p_object_id,
        p_old_value,
        p_new_value,
        p_description,
        inet_client_addr(),
        p_success,
        p_error_message
    );
END;
$$;

-- ============================================================
-- 5. Представления
-- ============================================================

CREATE OR REPLACE VIEW v_unprivileged AS
SELECT
    object_id,
    object_name,
    object_type,
    location,
    unit,
    current_value,
    last_update
FROM control_objects
WHERE is_active = TRUE
  AND is_commercial_secret = FALSE;

CREATE OR REPLACE VIEW v_operator AS
SELECT
    object_id,
    object_name,
    object_type,
    location,
    unit,
    current_value,
    last_update
FROM control_objects
WHERE is_active = TRUE
  AND is_commercial_secret = FALSE;

CREATE OR REPLACE VIEW v_engineer AS
SELECT
    object_id,
    object_name,
    object_type,
    location,
    unit,
    min_limit,
    max_limit,
    current_value,
    last_update,
    is_commercial_secret
FROM control_objects
WHERE is_active = TRUE;

CREATE OR REPLACE VIEW v_privileged AS
SELECT
    object_id,
    object_name,
    object_type,
    location,
    unit,
    min_limit,
    max_limit,
    current_value,
    last_update,
    is_commercial_secret
FROM control_objects
WHERE is_active = TRUE;

CREATE OR REPLACE VIEW v_admin_objects AS
SELECT
    object_id,
    object_name,
    object_type,
    location,
    unit,
    min_limit,
    max_limit,
    current_value,
    last_update,
    is_commercial_secret,
    is_active
FROM control_objects;

CREATE OR REPLACE VIEW v_admin_users AS
SELECT
    u.user_id,
    u.full_name,
    u.login,
    p.position_name,
    r.role_name,
    u.is_active,
    u.created_at,
    u.updated_at
FROM users u
LEFT JOIN positions p ON p.position_id = u.position_id
LEFT JOIN roles r ON r.role_id = u.role_id
WHERE check_policy('READ', 'USERS');

CREATE OR REPLACE VIEW v_user_rights_matrix AS
SELECT
    u.user_id,
    u.full_name,
    u.login,
    u.is_active,
    r.role_name,
    p.permission_code,
    p.description AS permission_description,
    rp.is_allowed,
    r.can_read,
    r.can_write,
    r.can_execute,
    r.can_manage_users,
    r.can_audit
FROM users u
JOIN roles r ON r.role_id = u.role_id
LEFT JOIN role_permissions rp ON rp.role_id = r.role_id
LEFT JOIN permissions p ON p.permission_id = rp.permission_id
WHERE check_policy('READ', 'RIGHTS_MATRIX')
   OR u.login = f_current_app_login();

CREATE OR REPLACE VIEW v_my_role AS
SELECT
    u.login,
    u.full_name,
    r.role_name
FROM users u
JOIN roles r ON r.role_id = u.role_id
WHERE u.login = f_current_app_login()
  AND u.is_active = TRUE;

CREATE OR REPLACE VIEW v_ib_logs AS
SELECT
    *
FROM access_log
WHERE check_policy('READ', 'ACCESS_LOG');

-- ============================================================
-- 6. Модифицируемое представление с INSTEAD OF триггером
-- ============================================================

CREATE OR REPLACE FUNCTION tr_v_admin_objects_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_success BOOLEAN;
BEGIN
    IF NOT check_policy('WRITE', 'PARAMETER') THEN
        PERFORM log_error('42501', 'Недостаточно прав для изменения объекта через v_admin_objects', NULL);
        PERFORM log_access(
            'POLICY_DENY',
            'Предупреждение',
            OLD.object_id,
            OLD.current_value,
            NEW.current_value,
            'Отказ изменения объекта через v_admin_objects',
            FALSE,
            'policy denied'
        );
        RETURN OLD;
    END IF;

    SELECT success
    INTO v_success
    FROM sp_update_parameter(NEW.object_id, NEW.current_value)
    LIMIT 1;

    IF v_success THEN
        RETURN NEW;
    END IF;

    RETURN OLD;
END;
$$;

CREATE TRIGGER tr_instead_update_admin_objects
INSTEAD OF UPDATE ON v_admin_objects
FOR EACH ROW EXECUTE PROCEDURE tr_v_admin_objects_update();

-- ============================================================
-- 7. Функции бизнес-логики
-- ============================================================

CREATE OR REPLACE FUNCTION f_get_my_role()
RETURNS TABLE(login TEXT, full_name VARCHAR, role_name VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.login::TEXT,
        u.full_name,
        r.role_name
    FROM users u
    JOIN roles r ON r.role_id = u.role_id
    WHERE u.login = f_current_app_login()
      AND u.is_active = TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION f_get_public_params()
RETURNS TABLE(object_name VARCHAR, current_value REAL, unit VARCHAR, location VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'PUBLIC_PARAMS') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр открытых параметров', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ просмотра открытых параметров', FALSE, 'policy denied');
        RETURN;
    END IF;

    PERFORM log_access('VIEW_OBJECT', 'Информационное сообщение', NULL, NULL, NULL, 'Просмотр открытых технологических параметров', TRUE, NULL);

    RETURN QUERY
    SELECT
        v.object_name,
        v.current_value,
        v.unit,
        v.location
    FROM v_unprivileged v
    ORDER BY v.object_name;
END;
$$;

CREATE OR REPLACE FUNCTION f_get_current_params()
RETURNS TABLE(object_name VARCHAR, current_value REAL, unit VARCHAR, location VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'PUBLIC_PARAMS') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр параметров оператора', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ просмотра параметров оператора', FALSE, 'policy denied');
        RETURN;
    END IF;

    PERFORM log_access('VIEW_OBJECT', 'Информационное сообщение', NULL, NULL, NULL, 'Просмотр параметров оператором', TRUE, NULL);

    RETURN QUERY
    SELECT
        v.object_name,
        v.current_value,
        v.unit,
        v.location
    FROM v_operator v
    ORDER BY v.object_name;
END;
$$;

CREATE OR REPLACE FUNCTION f_get_all_params()
RETURNS TABLE(
    object_id INTEGER,
    object_name VARCHAR,
    current_value REAL,
    unit VARCHAR,
    location VARCHAR,
    is_commercial_secret BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'ALL_PARAMS') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр всех параметров', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ просмотра всех параметров', FALSE, 'policy denied');
        RETURN;
    END IF;

    PERFORM log_access('VIEW_OBJECT', 'Информационное сообщение', NULL, NULL, NULL, 'Просмотр всех технологических параметров', TRUE, NULL);

    RETURN QUERY
    SELECT
        v.object_id,
        v.object_name,
        v.current_value,
        v.unit,
        v.location,
        v.is_commercial_secret
    FROM v_engineer v
    ORDER BY v.object_name;
END;
$$;

CREATE OR REPLACE FUNCTION sp_update_parameter(
    p_object_id INTEGER,
    p_new_value REAL
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_old_value REAL;
    v_min_limit REAL;
    v_max_limit REAL;
    v_object_name VARCHAR;
    v_event_type_name TEXT := 'Информационное сообщение';
    v_description TEXT;
    v_context TEXT;
BEGIN
    IF NOT check_policy('WRITE', 'PARAMETER') THEN
        PERFORM log_error('42501', 'Недостаточно прав для изменения параметра', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', p_object_id, NULL, p_new_value, 'Отказ изменения параметра', FALSE, 'policy denied');
        RETURN QUERY SELECT FALSE, 'Операция отклонена. Обратитесь к администратору безопасности.';
        RETURN;
    END IF;

    IF p_object_id IS NULL OR p_new_value IS NULL THEN
        PERFORM log_error('22004', 'Некорректные входные параметры функции sp_update_parameter', NULL);
        PERFORM log_access('UPDATE_VALUE', 'Предупреждение', p_object_id, NULL, p_new_value, 'Некорректные входные параметры изменения параметра', FALSE, 'bad input');
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Проверьте введенные данные.';
        RETURN;
    END IF;

    SELECT
        current_value,
        min_limit,
        max_limit,
        object_name
    INTO
        v_old_value,
        v_min_limit,
        v_max_limit,
        v_object_name
    FROM control_objects
    WHERE object_id = p_object_id
      AND is_active = TRUE;

    IF NOT FOUND THEN
        PERFORM log_error('P0002', 'Технологический объект не найден', NULL);
        PERFORM log_access('UPDATE_VALUE', 'Предупреждение', p_object_id, NULL, p_new_value, 'Попытка изменения несуществующего объекта', FALSE, 'object not found');
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Объект не найден или недоступен.';
        RETURN;
    END IF;

    IF (v_min_limit IS NOT NULL AND p_new_value < v_min_limit)
       OR (v_max_limit IS NOT NULL AND p_new_value > v_max_limit) THEN
        v_event_type_name := 'Авария';
        v_description := 'АВАРИЯ: параметр "' || v_object_name || '" вышел за допустимые границы. Старое значение: '
                         || COALESCE(v_old_value::TEXT, 'NULL') || ', новое значение: '
                         || p_new_value::TEXT;
    ELSE
        v_description := 'Изменение параметра "' || v_object_name || '". Старое значение: '
                         || COALESCE(v_old_value::TEXT, 'NULL') || ', новое значение: '
                         || p_new_value::TEXT;
    END IF;

    PERFORM set_config('asu.internal_update', '1', TRUE);

    UPDATE control_objects
    SET current_value = p_new_value,
        last_update = CURRENT_TIMESTAMP
    WHERE object_id = p_object_id;

    PERFORM log_access(
        'UPDATE_VALUE',
        v_event_type_name,
        p_object_id,
        v_old_value,
        p_new_value,
        v_description,
        TRUE,
        NULL
    );

    IF v_event_type_name = 'Авария' THEN
        INSERT INTO alarm_log (
            object_id,
            event_type_id,
            description,
            status
        )
        VALUES (
            p_object_id,
            (SELECT event_type_id FROM event_types WHERE type_name = 'Авария'),
            v_description,
            'ACTIVE'
        );
    END IF;

    RETURN QUERY SELECT TRUE, 'Операция выполнена успешно.';
    RETURN;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;

    PERFORM log_error(SQLSTATE, SQLERRM, v_context);
    PERFORM log_access(
        'UPDATE_VALUE',
        'Предупреждение',
        p_object_id,
        NULL,
        p_new_value,
        'Внутренняя ошибка при изменении параметра',
        FALSE,
        SQLERRM
    );

    RETURN QUERY SELECT FALSE, 'Операция не выполнена. Обратитесь к администратору безопасности.';
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION f_get_active_alarms(p_limit INTEGER DEFAULT 20)
RETURNS TABLE(
    alarm_id BIGINT,
    description TEXT,
    action_date TIMESTAMP,
    object_name VARCHAR,
    severity_level INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'ALARMS') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр аварий', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ просмотра аварий', FALSE, 'policy denied');
        RETURN;
    END IF;

    PERFORM log_access('VIEW_OBJECT', 'Информационное сообщение', NULL, NULL, NULL, 'Просмотр активных аварий', TRUE, NULL);

    RETURN QUERY
    SELECT
        a.alarm_id,
        a.description,
        a.alarm_time,
        c.object_name,
        e.severity_level
    FROM alarm_log a
    LEFT JOIN control_objects c ON c.object_id = a.object_id
    LEFT JOIN event_types e ON e.event_type_id = a.event_type_id
    WHERE a.status = 'ACTIVE'
    ORDER BY a.alarm_time DESC
    LIMIT COALESCE(p_limit, 20);
END;
$$;

CREATE OR REPLACE FUNCTION f_confirm_alarm(p_alarm_id BIGINT)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_object_id INTEGER;
    v_context TEXT;
BEGIN
    IF NOT check_policy('CONFIRM', 'ALARM') THEN
        PERFORM log_error('42501', 'Недостаточно прав для подтверждения аварии', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ подтверждения аварии', FALSE, 'policy denied');
        RETURN QUERY SELECT FALSE, 'Операция отклонена. Обратитесь к администратору безопасности.';
        RETURN;
    END IF;

    IF p_alarm_id IS NULL THEN
        PERFORM log_error('22004', 'Не указан идентификатор аварии', NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Проверьте введенные данные.';
        RETURN;
    END IF;

    SELECT object_id INTO v_object_id
    FROM alarm_log
    WHERE alarm_id = p_alarm_id
      AND status = 'ACTIVE';

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Активная авария не найдена.';
        RETURN;
    END IF;

    UPDATE alarm_log
    SET status = 'CONFIRMED',
        confirmed_by = get_current_user_id(),
        confirmed_at = CURRENT_TIMESTAMP
    WHERE alarm_id = p_alarm_id;

    PERFORM log_access('CONFIRM_ALARM', 'Информационное сообщение', v_object_id, NULL, NULL, 'Подтверждена авария ID=' || p_alarm_id::TEXT, TRUE, NULL);

    RETURN QUERY SELECT TRUE, 'Авария подтверждена.';
    RETURN;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;
    PERFORM log_error(SQLSTATE, SQLERRM, v_context);
    RETURN QUERY SELECT FALSE, 'Операция не выполнена. Обратитесь к администратору безопасности.';
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION f_get_change_log(p_limit INTEGER DEFAULT 50)
RETURNS TABLE(description TEXT, action_date TIMESTAMP, success BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'CHANGE_LOG') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр журнала изменений', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ просмотра журнала изменений', FALSE, 'policy denied');
        RETURN;
    END IF;

    PERFORM log_access('READ_LOG', 'Информационное сообщение', NULL, NULL, NULL, 'Просмотр журнала изменений параметров', TRUE, NULL);

    RETURN QUERY
    SELECT
        l.description,
        l.action_date,
        l.success
    FROM access_log l
    JOIN action_types a ON a.action_type_id = l.action_type_id
    WHERE a.action_name = 'UPDATE_VALUE'
    ORDER BY l.action_date DESC
    LIMIT COALESCE(p_limit, 50);
END;
$$;

CREATE OR REPLACE FUNCTION f_list_users()
RETURNS TABLE(
    user_id INTEGER,
    full_name VARCHAR,
    login VARCHAR,
    position_name VARCHAR,
    role_name VARCHAR,
    is_active BOOLEAN,
    created_at TIMESTAMP
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'USERS') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр пользователей', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ просмотра пользователей', FALSE, 'policy denied');
        RETURN;
    END IF;

    PERFORM log_access('VIEW_OBJECT', 'Информационное сообщение', NULL, NULL, NULL, 'Просмотр списка пользователей', TRUE, NULL);

    RETURN QUERY
    SELECT
        v.user_id,
        v.full_name,
        v.login,
        v.position_name,
        v.role_name,
        v.is_active,
        v.created_at
    FROM v_admin_users v
    ORDER BY v.user_id;
END;
$$;

CREATE OR REPLACE FUNCTION sp_add_user(
    p_full_name VARCHAR,
    p_login VARCHAR,
    p_password VARCHAR,
    p_position_name VARCHAR,
    p_role_name VARCHAR,
    p_is_active BOOLEAN DEFAULT TRUE
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_login VARCHAR(50);
    v_db_user TEXT;
    v_position_id INTEGER;
    v_role_id INTEGER;
    v_app_role TEXT;
    v_user_id INTEGER;
    v_context TEXT;
BEGIN
    IF NOT check_policy('MANAGE', 'USERS') THEN
        PERFORM log_error('42501', 'Недостаточно прав для добавления пользователя', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ добавления пользователя', FALSE, 'policy denied');
        RETURN QUERY SELECT FALSE, 'Операция отклонена. Обратитесь к администратору безопасности.';
        RETURN;
    END IF;

    IF p_login IS NULL OR btrim(p_login) = ''
       OR p_password IS NULL OR length(p_password) < 8
       OR p_full_name IS NULL OR btrim(p_full_name) = '' THEN
        PERFORM log_error('22004', 'Некорректные параметры добавления пользователя', NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Проверьте данные; пароль должен содержать не менее 8 символов.';
        RETURN;
    END IF;

    v_login := lower(btrim(p_login));

    IF v_login LIKE 'user_%' THEN
        v_login := substring(v_login FROM 6);
    END IF;

    IF v_login !~ '^[a-z][a-z0-9_]{2,30}$' THEN
        PERFORM log_error('22023', 'Логин не соответствует допустимому формату: ' || v_login, NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Логин должен содержать латинские буквы, цифры и знак подчеркивания.';
        RETURN;
    END IF;

    SELECT position_id INTO v_position_id
    FROM positions
    WHERE position_name = p_position_name;

    IF v_position_id IS NULL THEN
        PERFORM log_error('P0002', 'Должность не найдена: ' || COALESCE(p_position_name, 'NULL'), NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Должность не найдена.';
        RETURN;
    END IF;

    SELECT role_id INTO v_role_id
    FROM roles
    WHERE role_name = p_role_name;

    IF v_role_id IS NULL THEN
        PERFORM log_error('P0002', 'Роль не найдена: ' || COALESCE(p_role_name, 'NULL'), NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Роль не найдена.';
        RETURN;
    END IF;

    v_app_role :=
        CASE p_role_name
            WHEN 'Непривилегированный' THEN 'app_unprivileged'
            WHEN 'Оператор' THEN 'app_operator'
            WHEN 'Привилегированный' THEN 'app_privileged'
            WHEN 'Инженер' THEN 'app_engineer'
            WHEN 'Администратор ИС' THEN 'app_admin'
            WHEN 'Администратор ИБ' THEN 'app_ib_admin'
            ELSE NULL
        END;

    IF v_app_role IS NULL THEN
        PERFORM log_error('P0002', 'Не найдена роль PostgreSQL для роли: ' || COALESCE(p_role_name, 'NULL'), NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Роль пользователя не поддерживается.';
        RETURN;
    END IF;

    v_db_user := 'user_' || v_login;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_db_user) THEN
        EXECUTE 'ALTER USER ' || quote_ident(v_db_user) || ' WITH PASSWORD ' || quote_literal(p_password);
    ELSE
        EXECUTE 'CREATE USER ' || quote_ident(v_db_user) || ' WITH PASSWORD ' || quote_literal(p_password);
    END IF;

    EXECUTE 'REVOKE app_unprivileged, app_operator, app_privileged, app_engineer, app_admin, app_ib_admin FROM ' || quote_ident(v_db_user);
    EXECUTE 'GRANT ' || quote_ident(v_app_role) || ' TO ' || quote_ident(v_db_user);

    IF COALESCE(p_is_active, TRUE) THEN
        EXECUTE 'ALTER USER ' || quote_ident(v_db_user) || ' WITH LOGIN';
    ELSE
        EXECUTE 'ALTER USER ' || quote_ident(v_db_user) || ' WITH NOLOGIN';
    END IF;

    INSERT INTO users (
        full_name,
        login,
        position_id,
        role_id,
        is_active
    )
    VALUES (
        p_full_name,
        v_login,
        v_position_id,
        v_role_id,
        COALESCE(p_is_active, TRUE)
    )
    ON CONFLICT (login) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        position_id = EXCLUDED.position_id,
        role_id = EXCLUDED.role_id,
        is_active = EXCLUDED.is_active,
        updated_at = CURRENT_TIMESTAMP
    RETURNING user_id INTO v_user_id;

    PERFORM log_access('ADD_USER', 'Информационное сообщение', NULL, NULL, NULL, 'Добавлен или обновлен пользователь ' || v_login, TRUE, NULL);

    RETURN QUERY SELECT TRUE, 'Пользователь добавлен или обновлен.';
    RETURN;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;

    PERFORM log_error(SQLSTATE, SQLERRM, v_context);
    PERFORM log_access('ADD_USER', 'Предупреждение', NULL, NULL, NULL, 'Ошибка добавления пользователя', FALSE, SQLERRM);

    RETURN QUERY SELECT FALSE, 'Операция не выполнена. Обратитесь к администратору безопасности.';
    RETURN;
END;
$$;

-- выполняет безопасную блокировку, а не физическое удаление.
CREATE OR REPLACE FUNCTION sp_delete_user(p_user_id INTEGER)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_login VARCHAR(50);
    v_db_user TEXT;
    v_role_name VARCHAR(50);
    v_active_admins INTEGER;
    v_context TEXT;
BEGIN
    IF NOT check_policy('MANAGE', 'USERS') THEN
        PERFORM log_error('42501', 'Недостаточно прав для блокировки пользователя', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ блокировки пользователя', FALSE, 'policy denied');
        RETURN QUERY SELECT FALSE, 'Операция отклонена. Обратитесь к администратору безопасности.';
        RETURN;
    END IF;

    IF p_user_id IS NULL THEN
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Проверьте введенные данные.';
        RETURN;
    END IF;

    SELECT u.login, r.role_name
    INTO v_login, v_role_name
    FROM users u
    JOIN roles r ON r.role_id = u.role_id
    WHERE u.user_id = p_user_id;

    IF NOT FOUND THEN
        PERFORM log_error('P0002', 'Пользователь для блокировки не найден', NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Пользователь не найден.';
        RETURN;
    END IF;

    IF v_role_name = 'Администратор ИС' THEN
        SELECT COUNT(*)
        INTO v_active_admins
        FROM users u
        JOIN roles r ON r.role_id = u.role_id
        WHERE r.role_name = 'Администратор ИС'
          AND u.is_active = TRUE
          AND u.user_id <> p_user_id;

        IF v_active_admins < 1 THEN
            PERFORM log_error('P0001', 'Попытка блокировки последнего администратора ИС', NULL);
            RETURN QUERY SELECT FALSE, 'Операция не выполнена. Нельзя заблокировать последнего администратора ИС.';
            RETURN;
        END IF;
    END IF;

    UPDATE users
    SET is_active = FALSE,
        updated_at = CURRENT_TIMESTAMP
    WHERE user_id = p_user_id;

    v_db_user := 'user_' || v_login;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_db_user) THEN
        EXECUTE 'ALTER USER ' || quote_ident(v_db_user) || ' WITH NOLOGIN';
    END IF;

    PERFORM log_access('BLOCK_USER', 'Информационное сообщение', NULL, NULL, NULL, 'Заблокирован пользователь ' || v_login, TRUE, NULL);

    RETURN QUERY SELECT TRUE, 'Пользователь заблокирован.';
    RETURN;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;

    PERFORM log_error(SQLSTATE, SQLERRM, v_context);
    PERFORM log_access('BLOCK_USER', 'Предупреждение', NULL, NULL, NULL, 'Ошибка блокировки пользователя', FALSE, SQLERRM);

    RETURN QUERY SELECT FALSE, 'Операция не выполнена. Обратитесь к администратору безопасности.';
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION f_get_logs(p_limit INTEGER DEFAULT 100)
RETURNS TABLE(
    log_id BIGINT,
    db_user TEXT,
    event_type TEXT,
    action_name TEXT,
    object_id INTEGER,
    ip_address INET,
    action_date TIMESTAMP,
    success BOOLEAN,
    description TEXT,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'ACCESS_LOG') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр журнала операций', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ просмотра журнала операций', FALSE, 'policy denied');
        RETURN;
    END IF;

    PERFORM log_access('READ_LOG', 'Информационное сообщение', NULL, NULL, NULL, 'Просмотр полного журнала операций', TRUE, NULL);

    RETURN QUERY
    SELECT
        l.log_id,
        l.db_user::TEXT,
        COALESCE(et.type_name, '')::TEXT,
        COALESCE(at.action_name, '')::TEXT,
        l.object_id,
        l.ip_address,
        l.action_date,
        l.success,
        COALESCE(l.description, '')::TEXT,
        COALESCE(l.error_message, '')::TEXT
    FROM access_log l
    LEFT JOIN event_types et ON et.event_type_id = l.event_type_id
    LEFT JOIN action_types at ON at.action_type_id = l.action_type_id
    ORDER BY l.action_date DESC
    LIMIT COALESCE(p_limit, 100);
END;
$$;


CREATE OR REPLACE FUNCTION f_get_positions()
RETURNS TABLE(position_name VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'USERS') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр должностей', NULL);
        RETURN;
    END IF;

    RETURN QUERY
    SELECT p.position_name
    FROM positions p
    ORDER BY p.position_name;
END;
$$;

CREATE OR REPLACE FUNCTION f_get_roles()
RETURNS TABLE(role_name VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'USERS') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр ролей', NULL);
        RETURN;
    END IF;

    RETURN QUERY
    SELECT r.role_name
    FROM roles r
    ORDER BY r.role_name;
END;
$$;

CREATE OR REPLACE FUNCTION f_get_access_matrix()
RETURNS TABLE(
    role_name VARCHAR,
    permission_code VARCHAR,
    permission_description TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
    SELECT
        r.role_name,
        p.permission_code,
        COALESCE(p.description, '')::TEXT
    FROM roles r
    JOIN role_permissions rp ON rp.role_id = r.role_id
    JOIN permissions p ON p.permission_id = rp.permission_id
    WHERE rp.is_allowed = TRUE
    ORDER BY r.role_id, p.permission_code;
$$;



-- Дополнительные функции финальной версии приложения
CREATE OR REPLACE FUNCTION f_log_login()
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_login TEXT;
    v_context TEXT;
BEGIN
    v_login := f_current_app_login();

    UPDATE users
    SET last_login_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE login = v_login
      AND is_active = TRUE;

    PERFORM log_access('LOGIN', 'Информационное сообщение', NULL, NULL, NULL, 'Вход пользователя в приложение', TRUE, NULL);

    RETURN QUERY SELECT TRUE, 'Вход зафиксирован.';
    RETURN;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;
    PERFORM log_error(SQLSTATE, SQLERRM, v_context);
    RETURN QUERY SELECT FALSE, 'Операция аудита не выполнена.';
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION f_log_logout()
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_context TEXT;
BEGIN
    PERFORM log_access('LOGOUT', 'Информационное сообщение', NULL, NULL, NULL, 'Выход пользователя из приложения', TRUE, NULL);
    RETURN QUERY SELECT TRUE, 'Выход зафиксирован.';
    RETURN;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;
    PERFORM log_error(SQLSTATE, SQLERRM, v_context);
    RETURN QUERY SELECT FALSE, 'Операция аудита не выполнена.';
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION f_get_login_log(p_limit INTEGER DEFAULT 100)
RETURNS TABLE(
    log_id BIGINT,
    db_user TEXT,
    action_name TEXT,
    action_date TIMESTAMP,
    success BOOLEAN,
    description TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'ACCESS_LOG') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр журнала входов/выходов', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ просмотра журнала входов/выходов', FALSE, 'policy denied');
        RETURN;
    END IF;

    PERFORM log_access('READ_LOG', 'Информационное сообщение', NULL, NULL, NULL, 'Просмотр журнала входов/выходов', TRUE, NULL);

    RETURN QUERY
    SELECT
        l.log_id,
        l.db_user::TEXT,
        a.action_name::TEXT,
        l.action_date,
        l.success,
        COALESCE(l.description, '')::TEXT
    FROM access_log l
    JOIN action_types a ON a.action_type_id = l.action_type_id
    WHERE a.action_name IN ('LOGIN', 'LOGOUT')
    ORDER BY l.action_date DESC
    LIMIT COALESCE(p_limit, 100);
END;
$$;

CREATE OR REPLACE FUNCTION f_get_parameter_history(
    p_object_id INTEGER,
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE(
    action_date TIMESTAMP,
    db_user TEXT,
    old_value REAL,
    new_value REAL,
    success BOOLEAN,
    description TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
BEGIN
    IF NOT check_policy('READ', 'CHANGE_LOG') THEN
        PERFORM log_error('42501', 'Недостаточно прав на просмотр истории параметра', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', p_object_id, NULL, NULL, 'Отказ просмотра истории параметра', FALSE, 'policy denied');
        RETURN;
    END IF;

    IF p_object_id IS NULL THEN
        PERFORM log_error('22004', 'Не указан идентификатор параметра для просмотра истории', NULL);
        RETURN;
    END IF;

    PERFORM log_access('READ_LOG', 'Информационное сообщение', p_object_id, NULL, NULL, 'Просмотр истории параметра ID=' || p_object_id::TEXT, TRUE, NULL);

    RETURN QUERY
    SELECT
        l.action_date,
        l.db_user::TEXT,
        l.old_value,
        l.new_value,
        l.success,
        COALESCE(l.description, '')::TEXT
    FROM access_log l
    JOIN action_types a ON a.action_type_id = l.action_type_id
    WHERE a.action_name = 'UPDATE_VALUE'
      AND l.object_id = p_object_id
    ORDER BY l.action_date DESC
    LIMIT COALESCE(p_limit, 100);
END;
$$;

CREATE OR REPLACE FUNCTION sp_change_user_password(
    p_user_id INTEGER,
    p_new_password VARCHAR
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_login VARCHAR(50);
    v_db_user TEXT;
    v_context TEXT;
BEGIN
    IF NOT check_policy('MANAGE', 'USERS') THEN
        PERFORM log_error('42501', 'Недостаточно прав для смены пароля пользователя', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ смены пароля пользователя', FALSE, 'policy denied');
        RETURN QUERY SELECT FALSE, 'Операция отклонена. Обратитесь к администратору безопасности.';
        RETURN;
    END IF;

    IF p_user_id IS NULL OR p_new_password IS NULL OR length(p_new_password) < 8 THEN
        PERFORM log_error('22023', 'Некорректные параметры смены пароля', NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Пароль должен содержать не менее 8 символов.';
        RETURN;
    END IF;

    SELECT login INTO v_login
    FROM users
    WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        PERFORM log_error('P0002', 'Пользователь для смены пароля не найден', NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Пользователь не найден.';
        RETURN;
    END IF;

    v_db_user := 'user_' || v_login;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_db_user) THEN
        EXECUTE 'ALTER USER ' || quote_ident(v_db_user) || ' WITH PASSWORD ' || quote_literal(p_new_password);
    ELSE
        PERFORM log_error('P0002', 'Пользователь PostgreSQL не найден: ' || v_db_user, NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Учетная запись БД не найдена.';
        RETURN;
    END IF;

    UPDATE users
    SET updated_at = CURRENT_TIMESTAMP
    WHERE user_id = p_user_id;

    PERFORM log_access('CHANGE_PASSWORD', 'Информационное сообщение', NULL, NULL, NULL, 'Сменен пароль пользователя ' || v_login, TRUE, NULL);

    RETURN QUERY SELECT TRUE, 'Пароль пользователя изменен.';
    RETURN;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;
    PERFORM log_error(SQLSTATE, SQLERRM, v_context);
    PERFORM log_access('CHANGE_PASSWORD', 'Предупреждение', NULL, NULL, NULL, 'Ошибка смены пароля пользователя', FALSE, SQLERRM);
    RETURN QUERY SELECT FALSE, 'Операция не выполнена. Обратитесь к администратору безопасности.';
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION sp_set_user_active(
    p_user_id INTEGER,
    p_is_active BOOLEAN
)
RETURNS TABLE(success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_login VARCHAR(50);
    v_db_user TEXT;
    v_role_name VARCHAR(50);
    v_active_admins INTEGER;
    v_context TEXT;
BEGIN
    IF NOT check_policy('MANAGE', 'USERS') THEN
        PERFORM log_error('42501', 'Недостаточно прав для изменения состояния пользователя', NULL);
        PERFORM log_access('POLICY_DENY', 'Предупреждение', NULL, NULL, NULL, 'Отказ изменения состояния пользователя', FALSE, 'policy denied');
        RETURN QUERY SELECT FALSE, 'Операция отклонена. Обратитесь к администратору безопасности.';
        RETURN;
    END IF;

    IF p_user_id IS NULL OR p_is_active IS NULL THEN
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Проверьте выбранного пользователя.';
        RETURN;
    END IF;

    SELECT u.login, r.role_name
    INTO v_login, v_role_name
    FROM users u
    JOIN roles r ON r.role_id = u.role_id
    WHERE u.user_id = p_user_id;

    IF NOT FOUND THEN
        PERFORM log_error('P0002', 'Пользователь для изменения состояния не найден', NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Пользователь не найден.';
        RETURN;
    END IF;

    -- Нельзя заблокировать последнего активного администратора ИС.
    IF p_is_active = FALSE AND v_role_name = 'Администратор ИС' THEN
        SELECT COUNT(*)
        INTO v_active_admins
        FROM users u
        JOIN roles r ON r.role_id = u.role_id
        WHERE r.role_name = 'Администратор ИС'
          AND u.is_active = TRUE
          AND u.user_id <> p_user_id;

        IF v_active_admins < 1 THEN
            PERFORM log_error('P0001', 'Попытка блокировки последнего администратора ИС', NULL);
            RETURN QUERY SELECT FALSE, 'Операция не выполнена. Нельзя заблокировать последнего администратора ИС.';
            RETURN;
        END IF;
    END IF;

    v_db_user := 'user_' || v_login;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_db_user) THEN
        PERFORM log_error('P0002', 'Учетная запись PostgreSQL не найдена: ' || v_db_user, NULL);
        RETURN QUERY SELECT FALSE, 'Операция не выполнена. Учетная запись БД не найдена.';
        RETURN;
    END IF;

    IF p_is_active THEN
        EXECUTE 'ALTER ROLE ' || quote_ident(v_db_user) || ' WITH LOGIN';
    ELSE
        EXECUTE 'ALTER ROLE ' || quote_ident(v_db_user) || ' WITH NOLOGIN';
    END IF;

    UPDATE users
    SET is_active = p_is_active,
        updated_at = CURRENT_TIMESTAMP
    WHERE user_id = p_user_id;

    IF p_is_active THEN
        PERFORM log_access('UNBLOCK_USER', 'Информационное сообщение', NULL, NULL, NULL, 'Разблокирован пользователь ' || v_login, TRUE, NULL);
        RETURN QUERY SELECT TRUE, 'Пользователь разблокирован.';
    ELSE
        PERFORM log_access('BLOCK_USER', 'Информационное сообщение', NULL, NULL, NULL, 'Заблокирован пользователь ' || v_login, TRUE, NULL);
        RETURN QUERY SELECT TRUE, 'Пользователь заблокирован.';
    END IF;
    RETURN;

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;
    PERFORM log_error(SQLSTATE, SQLERRM, v_context);
    PERFORM log_access('UPDATE_USER', 'Предупреждение', NULL, NULL, NULL, 'Ошибка изменения состояния пользователя', FALSE, SQLERRM);
    RETURN QUERY SELECT FALSE, 'Операция не выполнена. Обратитесь к администратору безопасности.';
    RETURN;
END;
$$;

-- ============================================================
-- 8. Триггеры на базовых таблицах
-- ============================================================

CREATE OR REPLACE FUNCTION trg_update_users_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_users_timestamp
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE PROCEDURE trg_update_users_timestamp();

CREATE OR REPLACE FUNCTION trg_protect_last_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_admin_role_id INTEGER;
    v_admin_count INTEGER;
BEGIN
    SELECT role_id INTO v_admin_role_id
    FROM roles
    WHERE role_name = 'Администратор ИС';

    IF TG_OP = 'DELETE' THEN
        IF OLD.role_id = v_admin_role_id THEN
            SELECT COUNT(*)
            INTO v_admin_count
            FROM users
            WHERE role_id = v_admin_role_id
              AND is_active = TRUE
              AND user_id <> OLD.user_id;

            IF v_admin_count < 1 THEN
                RAISE EXCEPTION 'Последний администратор ИС не может быть удален.';
            END IF;
        END IF;

        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF OLD.role_id = v_admin_role_id
           AND OLD.is_active = TRUE
           AND (NEW.is_active = FALSE OR NEW.role_id <> v_admin_role_id) THEN
            SELECT COUNT(*)
            INTO v_admin_count
            FROM users
            WHERE role_id = v_admin_role_id
              AND is_active = TRUE
              AND user_id <> OLD.user_id;

            IF v_admin_count < 1 THEN
                RAISE EXCEPTION 'Последний администратор ИС не может быть заблокирован или лишен роли.';
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_last_admin
BEFORE UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE PROCEDURE trg_protect_last_admin();

CREATE OR REPLACE FUNCTION trg_audit_control_objects()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = asu_schema, pg_temp
AS $$
DECLARE
    v_internal TEXT;
BEGIN
    BEGIN
        v_internal := current_setting('asu.internal_update');
    EXCEPTION WHEN OTHERS THEN
        v_internal := '0';
    END;

    IF v_internal = '1' THEN
        RETURN NEW;
    END IF;

    IF OLD.current_value IS DISTINCT FROM NEW.current_value THEN
        PERFORM log_access(
            'UPDATE_VALUE',
            'Предупреждение',
            NEW.object_id,
            OLD.current_value,
            NEW.current_value,
            'Изменение базовой таблицы control_objects в обход штатной функции',
            TRUE,
            NULL
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_control_objects
AFTER UPDATE OF current_value ON control_objects
FOR EACH ROW EXECUTE PROCEDURE trg_audit_control_objects();

-- ============================================================
-- 9. Тестовые записи журналов и аварий
-- ============================================================

INSERT INTO access_log (
    user_id,
    db_user,
    event_type_id,
    action_type_id,
    object_id,
    old_value,
    new_value,
    description,
    action_date,
    success
)
VALUES
    (
        (SELECT user_id FROM users WHERE login = 'operator'),
        'user_operator',
        (SELECT event_type_id FROM event_types WHERE type_name = 'Информационное сообщение'),
        (SELECT action_type_id FROM action_types WHERE action_name = 'LOGIN'),
        NULL,
        NULL,
        NULL,
        'Оператор вошел в систему',
        CURRENT_TIMESTAMP - INTERVAL '2 days',
        TRUE
    ),
    (
        (SELECT user_id FROM users WHERE login = 'engineer'),
        'user_engineer',
        (SELECT event_type_id FROM event_types WHERE type_name = 'Информационное сообщение'),
        (SELECT action_type_id FROM action_types WHERE action_name = 'UPDATE_VALUE'),
        (SELECT object_id FROM control_objects WHERE object_name = 'Температура камеры ТВО-1'),
        60,
        65,
        'Инженер изменил температуру камеры ТВО-1',
        CURRENT_TIMESTAMP - INTERVAL '1 day',
        TRUE
    ),
    (
        (SELECT user_id FROM users WHERE login = 'ib_admin'),
        'user_ib_admin',
        (SELECT event_type_id FROM event_types WHERE type_name = 'Информационное сообщение'),
        (SELECT action_type_id FROM action_types WHERE action_name = 'READ_LOG'),
        NULL,
        NULL,
        NULL,
        'Администратор ИБ просмотрел журнал операций',
        CURRENT_TIMESTAMP - INTERVAL '6 hours',
        TRUE
    )
ON CONFLICT DO NOTHING;

INSERT INTO alarm_log (
    object_id,
    event_type_id,
    description,
    alarm_time,
    status
)
VALUES
    (
        (SELECT object_id FROM control_objects WHERE object_name = 'Температура бетонной смеси'),
        (SELECT event_type_id FROM event_types WHERE type_name = 'Авария'),
        'АВАРИЯ: температура бетонной смеси вышла за допустимый предел',
        CURRENT_TIMESTAMP - INTERVAL '1 hour',
        'ACTIVE'
    ),
    (
        (SELECT object_id FROM control_objects WHERE object_name = 'Давление гидросистемы пресса П-1'),
        (SELECT event_type_id FROM event_types WHERE type_name = 'Предупреждение'),
        'Предупреждение: давление гидросистемы пресса приближается к верхней границе',
        CURRENT_TIMESTAMP - INTERVAL '30 minutes',
        'ACTIVE'
    )
ON CONFLICT DO NOTHING;

-- ============================================================
-- 10. Права доступа
-- ============================================================

GRANT USAGE ON SCHEMA asu_schema TO
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

-- Полностью закрываем прямой доступ к базовым таблицам и последовательностям
REVOKE ALL ON ALL TABLES IN SCHEMA asu_schema FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA asu_schema FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA asu_schema FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA asu_schema FROM
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

REVOKE ALL ON ALL SEQUENCES IN SCHEMA asu_schema FROM
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

-- Представления
GRANT SELECT ON v_my_role TO
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

GRANT SELECT ON v_unprivileged TO app_unprivileged;
GRANT SELECT ON v_operator TO app_operator;
GRANT SELECT ON v_engineer TO app_engineer;
GRANT SELECT ON v_privileged TO app_privileged;
GRANT SELECT, UPDATE ON v_admin_objects TO app_admin;
GRANT SELECT ON v_admin_users TO app_admin, app_ib_admin;
GRANT SELECT ON v_user_rights_matrix TO
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

-- Служебные функции, необходимые представлениям и приложению
GRANT EXECUTE ON FUNCTION f_current_app_login() TO
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

GRANT EXECUTE ON FUNCTION get_current_user_id() TO
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

GRANT EXECUTE ON FUNCTION check_policy(TEXT, TEXT) TO
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

-- Функции чтения
GRANT EXECUTE ON FUNCTION f_get_my_role() TO
    app_unprivileged,
    app_operator,
    app_privileged,
    app_engineer,
    app_admin,
    app_ib_admin;

GRANT EXECUTE ON FUNCTION f_get_public_params() TO app_unprivileged, app_operator, app_privileged, app_engineer, app_admin, app_ib_admin;
GRANT EXECUTE ON FUNCTION f_get_access_matrix() TO app_unprivileged, app_operator, app_privileged, app_engineer, app_admin, app_ib_admin;
GRANT EXECUTE ON FUNCTION f_get_current_params() TO app_operator, app_privileged, app_engineer, app_admin;
GRANT EXECUTE ON FUNCTION f_get_all_params() TO app_privileged, app_engineer, app_admin;
GRANT EXECUTE ON FUNCTION f_get_active_alarms(INTEGER) TO app_operator, app_privileged, app_engineer, app_admin, app_ib_admin;
GRANT EXECUTE ON FUNCTION f_get_change_log(INTEGER) TO app_privileged, app_engineer, app_admin, app_ib_admin;

-- Функции изменения
GRANT EXECUTE ON FUNCTION sp_update_parameter(INTEGER, REAL) TO app_privileged, app_engineer, app_admin;
GRANT EXECUTE ON FUNCTION f_confirm_alarm(BIGINT) TO app_operator, app_privileged, app_engineer, app_admin;

-- Администрирование пользователей
GRANT EXECUTE ON FUNCTION f_list_users() TO app_admin, app_ib_admin;
GRANT EXECUTE ON FUNCTION sp_add_user(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, BOOLEAN) TO app_admin;
GRANT EXECUTE ON FUNCTION sp_delete_user(INTEGER) TO app_admin;
GRANT EXECUTE ON FUNCTION f_get_positions() TO app_admin;
GRANT EXECUTE ON FUNCTION f_get_roles() TO app_admin;

-- Аудит
GRANT EXECUTE ON FUNCTION f_get_logs(INTEGER) TO app_ib_admin;


-- Дополнительные функции финального приложения
GRANT EXECUTE ON FUNCTION f_log_login() TO app_unprivileged, app_operator, app_privileged, app_engineer, app_admin, app_ib_admin;
GRANT EXECUTE ON FUNCTION f_log_logout() TO app_unprivileged, app_operator, app_privileged, app_engineer, app_admin, app_ib_admin;
GRANT EXECUTE ON FUNCTION f_get_login_log(INTEGER) TO app_ib_admin;
GRANT EXECUTE ON FUNCTION f_get_parameter_history(INTEGER, INTEGER) TO app_privileged, app_engineer, app_admin, app_ib_admin;
GRANT EXECUTE ON FUNCTION sp_change_user_password(INTEGER, VARCHAR) TO app_admin;
GRANT EXECUTE ON FUNCTION sp_set_user_active(INTEGER, BOOLEAN) TO app_admin;


-- LOGIN-учетные записи и их пароли настраиваются скриптом 02_demo_accounts.sql.

-- ============================================================
-- 11. Итоговая проверочная информация для владельца БД
-- ============================================================

SELECT 'База данных АСУ ТП «Автоматика» создана успешно.' AS result
UNION ALL
SELECT 'Пользователей в прикладной таблице: ' || COUNT(*)::TEXT FROM users
UNION ALL
SELECT 'Технологических объектов ЖБК: ' || COUNT(*)::TEXT FROM control_objects
UNION ALL
SELECT 'Записей в журнале операций: ' || COUNT(*)::TEXT FROM access_log
UNION ALL
SELECT 'Активных аварий: ' || COUNT(*)::TEXT FROM alarm_log WHERE status = 'ACTIVE';
