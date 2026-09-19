# dashboard_ops.py
# Сводная информация для главной панели приложения.
# Сводная информация для главного экрана.

from db_helpers import fetch_all


def _safe_count(conn, sql, params=None):
    try:
        rows = fetch_all(conn, sql, params)
        if rows and rows[0] and rows[0][0] is not None:
            return int(rows[0][0])
    except Exception:
        # Для сводной панели не прерываем работу приложения, если роль не имеет доступа
        # к отдельному разделу. В интерфейсе это будет скрыто от пользователя.
        pass
    return None


def get_dashboard_summary(conn, role_name):
    """Возвращает список строк (показатель, значение, пояснение)."""
    result = []
    role = role_name or ""

    public_params = _safe_count(conn, "SELECT COUNT(*) FROM asu_schema.f_get_public_params()")
    if public_params is not None:
        result.append(("Открытые параметры", public_params, "Параметры общего мониторинга"))

    if role in ("Оператор", "Привилегированный", "Инженер", "Администратор ИС"):
        current_params = _safe_count(conn, "SELECT COUNT(*) FROM asu_schema.f_get_current_params()")
        if current_params is not None:
            result.append(("Параметры оператора", current_params, "Рабочие параметры технологического процесса"))

    if role in ("Привилегированный", "Инженер", "Администратор ИС"):
        all_params = _safe_count(conn, "SELECT COUNT(*) FROM asu_schema.f_get_all_params()")
        if all_params is not None:
            result.append(("Все параметры", all_params, "Расширенный набор технологических параметров"))

    if role in ("Оператор", "Привилегированный", "Инженер", "Администратор ИС", "Администратор ИБ"):
        active_alarms = _safe_count(conn, "SELECT COUNT(*) FROM asu_schema.f_get_active_alarms(%s)", (1000,))
        if active_alarms is not None:
            result.append(("Активные аварии", active_alarms, "Неподтвержденные аварийные события"))

    if role in ("Администратор ИС", "Администратор ИБ"):
        users_count = _safe_count(conn, "SELECT COUNT(*) FROM asu_schema.f_list_users()")
        if users_count is not None:
            result.append(("Учетные записи", users_count, "Пользователи, зарегистрированные в системе"))

    if role == "Администратор ИБ":
        login_count = _safe_count(conn, "SELECT COUNT(*) FROM asu_schema.f_get_login_log(%s)", (1000,))
        if login_count is not None:
            result.append(("Входы и выходы", login_count, "Сеансы пользователей"))

    if not result:
        result.append(("Сводка", "—", "Для текущей роли нет дополнительных показателей" ))

    return result


def get_access_matrix_rows(conn):
    """Возвращает фактические разрешения ролей из PostgreSQL.

    Источник истины — role_permissions/permissions в БД, а не статический
    список в клиентском приложении.
    """
    return fetch_all(
        conn,
        "SELECT role_name, permission_code, permission_description "
        "FROM asu_schema.f_get_access_matrix()"
    )


def get_control_example_rows(role_name):
    rows = [
        ("1", "Вход в систему", "Все роли", "Вход по выданной учетной записи"),
        ("2", "Просмотр открытых параметров", "Все роли", "Операция доступна в разделе мониторинга"),
        ("3", "Просмотр закрытых параметров", "Инженер, привилегированный, администратор ИС", "Доступ ограничен назначенной ролью"),
        ("4", "Изменение параметра", "Инженер, привилегированный, администратор ИС", "Операция фиксируется в журнале"),
        ("5", "Подтверждение аварии", "Оператор, инженер, привилегированный, администратор ИС", "Событие переводится в обработанное состояние"),
        ("6", "Управление пользователями", "Администратор ИС", "Создание, блокировка и разблокировка учетных записей"),
        ("7", "Контроль входов и выходов", "Администратор ИБ", "Сеансы пользователей отображаются в отдельном журнале"),
        ("8", "Системные данные", "Администратор ИБ / администратор ИС", "Доступ предоставляется по служебной необходимости"),
    ]
    return rows
