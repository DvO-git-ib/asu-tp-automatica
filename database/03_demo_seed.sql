-- ============================================================
-- АСУ ТП «Автоматика» — скрипт массового наполнения БД
-- PostgreSQL 9.6 / Astra Linux «Орел» 1.7.5
-- Что добавляется:
--   - 60 синтетических неактивных учетных записей приложения;
--   - 120 дополнительных технологических параметров/объектов;
--   - 700 записей журнала операций;
--   - 250 записей журнала аварий.
-- ============================================================

SET client_encoding = 'UTF8';
SET search_path TO asu_schema, public;

-- ------------------------------------------------------------
-- 0. Очистка ранее сгенерированных журналов
-- ------------------------------------------------------------

DELETE FROM alarm_log
WHERE description LIKE '[SEED]%';

DELETE FROM access_log
WHERE description LIKE '[SEED]%';

-- ------------------------------------------------------------
-- 1. Дополнительные пользователи приложения
-- ------------------------------------------------------------
-- Пользователи создаются только как синтетические записи для демонстрации
-- интерфейса и журналов. LOGIN-роли PostgreSQL для них намеренно не создаются,
-- поэтому тестовые данные не добавляют общих или захардкоженных паролей.
-- ------------------------------------------------------------

WITH generated_users AS (
    SELECT
        i,
        CASE
            WHEN i BETWEEN 1 AND 20 THEN 'op' || lpad(i::text, 3, '0')
            WHEN i BETWEEN 21 AND 35 THEN 'eng' || lpad((i - 20)::text, 3, '0')
            WHEN i BETWEEN 36 AND 45 THEN 'unpriv' || lpad((i - 35)::text, 3, '0')
            WHEN i BETWEEN 46 AND 52 THEN 'priv' || lpad((i - 45)::text, 3, '0')
            WHEN i BETWEEN 53 AND 56 THEN 'adm' || lpad((i - 52)::text, 3, '0')
            ELSE 'ib' || lpad((i - 56)::text, 3, '0')
        END AS login,
        CASE
            WHEN i BETWEEN 1 AND 20 THEN 'Оператор ТП №' || lpad(i::text, 2, '0')
            WHEN i BETWEEN 21 AND 35 THEN 'Инженер АСУ ТП №' || lpad((i - 20)::text, 2, '0')
            WHEN i BETWEEN 36 AND 45 THEN 'Наблюдатель технологических параметров №' || lpad((i - 35)::text, 2, '0')
            WHEN i BETWEEN 46 AND 52 THEN 'Привилегированный пользователь №' || lpad((i - 45)::text, 2, '0')
            WHEN i BETWEEN 53 AND 56 THEN 'Администратор ИС №' || lpad((i - 52)::text, 2, '0')
            ELSE 'Администратор ИБ №' || lpad((i - 56)::text, 2, '0')
        END AS full_name,
        CASE
            WHEN i BETWEEN 1 AND 20 THEN 'Оператор ТП'
            WHEN i BETWEEN 21 AND 35 THEN 'Инженер АСУ ТП'
            WHEN i BETWEEN 36 AND 45 THEN 'Непривилегированный пользователь'
            WHEN i BETWEEN 46 AND 52 THEN 'Привилегированный пользователь'
            WHEN i BETWEEN 53 AND 56 THEN 'Администратор ИС'
            ELSE 'Администратор ИБ'
        END AS position_name,
        CASE
            WHEN i BETWEEN 1 AND 20 THEN 'Оператор'
            WHEN i BETWEEN 21 AND 35 THEN 'Инженер'
            WHEN i BETWEEN 36 AND 45 THEN 'Непривилегированный'
            WHEN i BETWEEN 46 AND 52 THEN 'Привилегированный'
            WHEN i BETWEEN 53 AND 56 THEN 'Администратор ИС'
            ELSE 'Администратор ИБ'
        END AS role_name
    FROM generate_series(1, 60) AS s(i)
)
INSERT INTO users (
    full_name,
    login,
    position_id,
    role_id,
    is_active,
    created_at,
    updated_at
)
SELECT
    gu.full_name,
    gu.login,
    p.position_id,
    r.role_id,
    FALSE,
    CURRENT_TIMESTAMP - ((gu.i % 90)::text || ' days')::interval,
    CURRENT_TIMESTAMP
FROM generated_users gu
JOIN positions p ON p.position_name = gu.position_name
JOIN roles r ON r.role_name = gu.role_name
ON CONFLICT (login) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    position_id = EXCLUDED.position_id,
    role_id = EXCLUDED.role_id,
    is_active = FALSE,
    updated_at = CURRENT_TIMESTAMP;

-- LOGIN-роли PostgreSQL для синтетических пользователей не создаются.

-- ------------------------------------------------------------
-- 2. Дополнительные технологические объекты и параметры АСУ ТП
-- ------------------------------------------------------------
-- Объекты создаются с уникальными именами вида «Параметр ЖБК-001 ...».
-- При повторном запуске уже существующие объекты не дублируются.
-- ------------------------------------------------------------

WITH generated_objects AS (
    SELECT
        i,
        'Параметр ЖБК-' || lpad(i::text, 3, '0') || ' - ' ||
        CASE (i % 8)
            WHEN 0 THEN 'температура камеры ТВО'
            WHEN 1 THEN 'влажность камеры ТВО'
            WHEN 2 THEN 'уровень материала в силосе'
            WHEN 3 THEN 'масса материала в дозаторе'
            WHEN 4 THEN 'давление гидросистемы'
            WHEN 5 THEN 'скорость конвейера'
            WHEN 6 THEN 'вибрация виброплощадки'
            ELSE 'состояние исполнительного механизма'
        END AS object_name,
        CASE (i % 8)
            WHEN 0 THEN 'датчик температуры'
            WHEN 1 THEN 'датчик влажности'
            WHEN 2 THEN 'датчик уровня'
            WHEN 3 THEN 'весовой дозатор'
            WHEN 4 THEN 'датчик давления'
            WHEN 5 THEN 'датчик скорости'
            WHEN 6 THEN 'датчик вибрации'
            ELSE 'исполнительный механизм'
        END AS object_type,
        'Цех №' || ((i % 4) + 1)::text || ', линия ЖБК-' || lpad(((i % 12) + 1)::text, 2, '0') AS location,
        CASE (i % 8)
            WHEN 0 THEN '°C'
            WHEN 1 THEN '%'
            WHEN 2 THEN '%'
            WHEN 3 THEN 'кг'
            WHEN 4 THEN 'МПа'
            WHEN 5 THEN 'м/с'
            WHEN 6 THEN 'мм/с'
            ELSE NULL
        END AS unit,
        CASE (i % 8)
            WHEN 0 THEN 20::real
            WHEN 1 THEN 40::real
            WHEN 2 THEN 5::real
            WHEN 3 THEN 0::real
            WHEN 4 THEN 1::real
            WHEN 5 THEN 0::real
            WHEN 6 THEN 0::real
            ELSE 0::real
        END AS min_limit,
        CASE (i % 8)
            WHEN 0 THEN 90::real
            WHEN 1 THEN 100::real
            WHEN 2 THEN 100::real
            WHEN 3 THEN 1500::real
            WHEN 4 THEN 25::real
            WHEN 5 THEN 5::real
            WHEN 6 THEN 15::real
            ELSE 1::real
        END AS max_limit,
        CASE (i % 8)
            WHEN 0 THEN (20 + (i % 60))::real
            WHEN 1 THEN (45 + (i % 45))::real
            WHEN 2 THEN (10 + (i % 85))::real
            WHEN 3 THEN (100 + ((i * 17) % 1200))::real
            WHEN 4 THEN (2 + (i % 18))::real
            WHEN 5 THEN ((i % 50)::real / 10.0)::real
            WHEN 6 THEN ((i % 120)::real / 10.0)::real
            ELSE (i % 2)::real
        END AS current_value,
        CASE WHEN (i % 5) IN (0, 1) THEN TRUE ELSE FALSE END AS is_commercial_secret
    FROM generate_series(1, 120) AS s(i)
)
INSERT INTO control_objects (
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
)
SELECT
    go.object_name,
    go.object_type,
    go.location,
    go.unit,
    go.min_limit,
    go.max_limit,
    go.current_value,
    CURRENT_TIMESTAMP - ((go.i % 1440)::text || ' minutes')::interval,
    go.is_commercial_secret,
    TRUE
FROM generated_objects go
WHERE NOT EXISTS (
    SELECT 1
    FROM control_objects co
    WHERE co.object_name = go.object_name
);

-- ------------------------------------------------------------
-- 3. Массовое заполнение журнала операций access_log
-- ------------------------------------------------------------
-- Создается 700 записей аудита: входы, выходы, просмотры, изменения,
-- отказы политики безопасности, служебные ошибки.
-- ------------------------------------------------------------

WITH arrays AS (
    SELECT
        (SELECT array_agg(user_id ORDER BY user_id) FROM users WHERE is_active = TRUE) AS user_ids,
        (SELECT array_agg(object_id ORDER BY object_id) FROM control_objects WHERE is_active = TRUE) AS object_ids
),
prepared AS (
    SELECT
        gs,
        a.user_ids[(gs % array_length(a.user_ids, 1)) + 1] AS user_id,
        a.object_ids[(gs % array_length(a.object_ids, 1)) + 1] AS object_id,
        CASE (gs % 10)
            WHEN 0 THEN 'LOGIN'
            WHEN 1 THEN 'LOGOUT'
            WHEN 2 THEN 'VIEW_OBJECT'
            WHEN 3 THEN 'UPDATE_VALUE'
            WHEN 4 THEN 'UPDATE_VALUE'
            WHEN 5 THEN 'CONFIRM_ALARM'
            WHEN 6 THEN 'READ_LOG'
            WHEN 7 THEN 'UPDATE_USER'
            WHEN 8 THEN 'POLICY_DENY'
            ELSE 'ERROR'
        END AS action_name
    FROM generate_series(1, 700) AS s(gs)
    CROSS JOIN arrays a
),
classified AS (
    SELECT
        p.*,
        CASE
            WHEN p.action_name IN ('POLICY_DENY', 'ERROR') THEN 'Предупреждение'
            WHEN p.action_name = 'UPDATE_VALUE' AND (p.gs % 13 = 0) THEN 'Авария'
            ELSE 'Информационное сообщение'
        END AS event_type_name,
        CASE
            WHEN p.action_name IN ('POLICY_DENY', 'ERROR') THEN FALSE
            ELSE TRUE
        END AS success_flag
    FROM prepared p
)
INSERT INTO access_log (
    user_id,
    db_user,
    event_type_id,
    action_type_id,
    object_id,
    old_value,
    new_value,
    action_date,
    description,
    ip_address,
    success,
    error_message
)
SELECT
    c.user_id,
    'seed_script',
    (SELECT event_type_id FROM event_types WHERE type_name = c.event_type_name),
    (SELECT action_type_id FROM action_types WHERE action_name = c.action_name),
    CASE
        WHEN c.action_name IN ('VIEW_OBJECT', 'UPDATE_VALUE', 'CONFIRM_ALARM') THEN c.object_id
        ELSE NULL
    END,
    CASE WHEN c.action_name = 'UPDATE_VALUE' THEN ((c.gs % 70) + 10)::real ELSE NULL END,
    CASE WHEN c.action_name = 'UPDATE_VALUE' THEN ((c.gs % 85) + 15)::real ELSE NULL END,
    CURRENT_TIMESTAMP - ((c.gs % 60)::text || ' days')::interval - ((c.gs % 1440)::text || ' minutes')::interval,
    '[SEED] ' ||
    CASE c.action_name
        WHEN 'LOGIN' THEN 'Вход пользователя в систему, запись №' || c.gs::text
        WHEN 'LOGOUT' THEN 'Выход пользователя из системы, запись №' || c.gs::text
        WHEN 'VIEW_OBJECT' THEN 'Просмотр технологического параметра, запись №' || c.gs::text
        WHEN 'UPDATE_VALUE' THEN 'Изменение технологического параметра, запись №' || c.gs::text
        WHEN 'CONFIRM_ALARM' THEN 'Подтверждение аварийного сообщения, запись №' || c.gs::text
        WHEN 'READ_LOG' THEN 'Просмотр журнала операций, запись №' || c.gs::text
        WHEN 'UPDATE_USER' THEN 'Изменение служебных данных пользователя, запись №' || c.gs::text
        WHEN 'POLICY_DENY' THEN 'Отказ политикой безопасности, запись №' || c.gs::text
        ELSE 'Служебная ошибка выполнения операции, запись №' || c.gs::text
    END,
    ('192.168.' || ((c.gs % 20) + 1)::text || '.' || ((c.gs % 200) + 20)::text)::inet,
    c.success_flag,
    CASE
        WHEN c.action_name = 'POLICY_DENY' THEN 'Действие отклонено политикой безопасности'
        WHEN c.action_name = 'ERROR' THEN 'Смоделированная служебная ошибка для проверки журнала'
        ELSE NULL
    END
FROM classified c;

-- ------------------------------------------------------------
-- 4. Массовое заполнение журнала аварий alarm_log
-- ------------------------------------------------------------
-- Создается 250 аварийных событий по технологическим параметрам.
-- ------------------------------------------------------------

WITH arrays AS (
    SELECT
        (SELECT array_agg(object_id ORDER BY object_id) FROM control_objects WHERE is_active = TRUE) AS object_ids,
        (SELECT array_agg(user_id ORDER BY user_id) FROM users WHERE is_active = TRUE) AS user_ids
),
prepared AS (
    SELECT
        gs,
        a.object_ids[(gs % array_length(a.object_ids, 1)) + 1] AS object_id,
        a.user_ids[(gs % array_length(a.user_ids, 1)) + 1] AS user_id,
        CASE
            WHEN gs % 25 = 0 THEN 'Критическая авария'
            ELSE 'Авария'
        END AS event_type_name,
        CASE
            WHEN gs % 5 = 0 THEN 'CLOSED'
            WHEN gs % 3 = 0 THEN 'CONFIRMED'
            ELSE 'ACTIVE'
        END AS alarm_status
    FROM generate_series(1, 250) AS s(gs)
    CROSS JOIN arrays a
)
INSERT INTO alarm_log (
    object_id,
    event_type_id,
    alarm_time,
    description,
    status,
    confirmed_by,
    confirmed_at
)
SELECT
    p.object_id,
    (SELECT event_type_id FROM event_types WHERE type_name = p.event_type_name),
    CURRENT_TIMESTAMP - ((p.gs % 45)::text || ' days')::interval - ((p.gs % 720)::text || ' minutes')::interval,
    '[SEED] ' || p.event_type_name || ' №' || p.gs::text || ': выход технологического параметра за допустимые пределы',
    p.alarm_status,
    CASE WHEN p.alarm_status IN ('CONFIRMED', 'CLOSED') THEN p.user_id ELSE NULL END,
    CASE
        WHEN p.alarm_status IN ('CONFIRMED', 'CLOSED')
        THEN CURRENT_TIMESTAMP - ((p.gs % 45)::text || ' days')::interval - ((p.gs % 600)::text || ' minutes')::interval
        ELSE NULL
    END
FROM prepared p;

-- ------------------------------------------------------------
-- 5. Итоговая проверка количества записей
-- ------------------------------------------------------------

WITH table_counts AS (
    SELECT 'positions' AS table_name, COUNT(*)::bigint AS row_count FROM positions
    UNION ALL SELECT 'roles', COUNT(*)::bigint FROM roles
    UNION ALL SELECT 'permissions', COUNT(*)::bigint FROM permissions
    UNION ALL SELECT 'role_permissions', COUNT(*)::bigint FROM role_permissions
    UNION ALL SELECT 'users', COUNT(*)::bigint FROM users
    UNION ALL SELECT 'event_types', COUNT(*)::bigint FROM event_types
    UNION ALL SELECT 'action_types', COUNT(*)::bigint FROM action_types
    UNION ALL SELECT 'control_objects', COUNT(*)::bigint FROM control_objects
    UNION ALL SELECT 'access_log', COUNT(*)::bigint FROM access_log
    UNION ALL SELECT 'alarm_log', COUNT(*)::bigint FROM alarm_log
)
SELECT table_name, row_count
FROM table_counts
UNION ALL
SELECT 'TOTAL_RECORDS', SUM(row_count)
FROM table_counts
ORDER BY table_name;

-- Дополнительная проверка: количество записей, созданных именно этим скриптом.
SELECT
    (SELECT COUNT(*) FROM users WHERE login ~ '^(op|eng|unpriv|priv|adm|ib)[0-9]{3}$') AS generated_users,
    (SELECT COUNT(*) FROM control_objects WHERE object_name LIKE 'Параметр ЖБК-%') AS generated_control_objects,
    (SELECT COUNT(*) FROM access_log WHERE description LIKE '[SEED]%') AS generated_access_log,
    (SELECT COUNT(*) FROM alarm_log WHERE description LIKE '[SEED]%') AS generated_alarm_log;
