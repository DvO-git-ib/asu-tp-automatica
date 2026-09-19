-- ============================================================
-- АСУ ТП «Автоматика» — финальная проверка БД
-- PostgreSQL 9.6
--
-- Запуск:
--   psql -U postgres -d asu_tp_db -f database/04_security_checks.sql
-- ============================================================

SET client_encoding = 'UTF8';
SET search_path TO asu_schema, public;

-- 1. Проверка основных таблиц
SELECT '1. Таблицы в asu_schema' AS section;
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'asu_schema'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- 2. Проверка, что удаленные служебные таблицы отсутствуют
SELECT '2. Проверка отсутствия неиспользуемых таблиц' AS section;
SELECT
    obj_name,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = 'asu_schema'
              AND table_name = obj_name
        )
        THEN 'ОСТАЛАСЬ'
        ELSE 'ОТСУТСТВУЕТ'
    END AS status
FROM (VALUES ('backup_log'), ('error_log')) AS t(obj_name);

-- 3. Количество данных
SELECT '3. Количество записей' AS section;
SELECT 'users' AS object_name, COUNT(*) AS rows_count FROM users
UNION ALL
SELECT 'roles', COUNT(*) FROM roles
UNION ALL
SELECT 'permissions', COUNT(*) FROM permissions
UNION ALL
SELECT 'role_permissions', COUNT(*) FROM role_permissions
UNION ALL
SELECT 'control_objects', COUNT(*) FROM control_objects
UNION ALL
SELECT 'access_log', COUNT(*) FROM access_log
UNION ALL
SELECT 'alarm_log', COUNT(*) FROM alarm_log
ORDER BY object_name;

-- 4. Пользователи приложения и роли
SELECT '4. Пользователи приложения' AS section;
SELECT
    u.login,
    u.full_name,
    r.role_name,
    u.is_active,
    u.created_at
FROM users u
JOIN roles r ON r.role_id = u.role_id
ORDER BY u.login;

-- 5. PostgreSQL-пользователи для приложения
SELECT '5. PostgreSQL-пользователи' AS section;
SELECT
    rolname,
    rolcanlogin
FROM pg_roles
WHERE rolname IN (
    'user_operator',
    'user_engineer',
    'user_admin',
    'user_ib_admin',
    'user_privileged',
    'user_unprivileged'
)
ORDER BY rolname;

-- 6. Матрица прав
SELECT '6. Матрица прав' AS section;
SELECT
    role_name,
    permission_code,
    permission_description
FROM f_get_access_matrix()
ORDER BY role_name, permission_code;

-- 7. Внешние ключи
SELECT '7. Внешние ключи' AS section;
SELECT
    conname AS fk_name,
    conrelid::regclass AS child_table,
    confrelid::regclass AS parent_table
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'asu_schema'::regnamespace
ORDER BY conrelid::regclass::text, conname;

-- 8. Проверка закрытия прямого доступа к базовым таблицам
SELECT '8. Проверка прямого доступа к таблицам' AS section;
SELECT
    grantee,
    table_name,
    has_table_privilege(grantee, 'asu_schema.' || table_name, 'SELECT') AS direct_select
FROM (
    VALUES
        ('user_unprivileged', 'users'),
        ('user_unprivileged', 'control_objects'),
        ('user_unprivileged', 'access_log'),
        ('user_operator', 'access_log'),
        ('user_engineer', 'control_objects'),
        ('user_admin', 'users'),
        ('user_ib_admin', 'access_log')
) AS p(grantee, table_name)
ORDER BY grantee, table_name;

-- 9. Проверка основных функций приложения от имени владельца БД
SELECT '9. Проверка функций' AS section;
SELECT 'f_get_public_params' AS function_name, COUNT(*) AS rows_count FROM f_get_public_params()
UNION ALL
SELECT 'f_get_current_params', COUNT(*) FROM f_get_current_params()
UNION ALL
SELECT 'f_get_all_params', COUNT(*) FROM f_get_all_params()
UNION ALL
SELECT 'f_get_active_alarms', COUNT(*) FROM f_get_active_alarms(100)
UNION ALL
SELECT 'f_list_users', COUNT(*) FROM f_list_users()
UNION ALL
SELECT 'f_get_login_log', COUNT(*) FROM f_get_login_log(100);

-- 10. Проверка ключевых EXECUTE-привилегий ролей
-- Это проверяет слой GRANT/REVOKE. Поведенческие проверки check_policy()
-- выполняются отдельными сессиями согласно docs/security-test-plan.md.
SELECT '10. Ключевые EXECUTE-привилегии' AS section;
WITH expected(grantee, function_signature, should_have) AS (
    VALUES
        ('user_unprivileged', 'asu_schema.f_get_public_params()', TRUE),
        ('user_unprivileged', 'asu_schema.f_get_all_params()', FALSE),
        ('user_operator', 'asu_schema.f_confirm_alarm(bigint)', TRUE),
        ('user_operator', 'asu_schema.sp_update_parameter(integer,real)', FALSE),
        ('user_engineer', 'asu_schema.sp_update_parameter(integer,real)', TRUE),
        ('user_admin', 'asu_schema.sp_set_user_active(integer,boolean)', TRUE),
        ('user_ib_admin', 'asu_schema.f_get_logs(integer)', TRUE),
        ('user_ib_admin', 'asu_schema.sp_set_user_active(integer,boolean)', FALSE)
), actual AS (
    SELECT
        grantee,
        function_signature,
        should_have,
        has_function_privilege(grantee, function_signature, 'EXECUTE') AS has_execute
    FROM expected
)
SELECT
    grantee,
    function_signature,
    should_have AS expected_execute,
    has_execute AS actual_execute,
    (should_have = has_execute) AS matches_expected
FROM actual
ORDER BY grantee, function_signature;

SELECT 'Проверка завершена.' AS result;
