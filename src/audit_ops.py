# audit_ops.py
# Журналирование входов/выходов и просмотр журнала входов.

from db_helpers import fetch_all, execute_status_function


def log_login(conn):
    """Фиксирует успешный вход пользователя в журнале БД."""
    return execute_status_function(
        conn,
        "SELECT success, message FROM asu_schema.f_log_login()"
    )


def log_logout(conn):
    """Фиксирует выход пользователя из системы в журнале БД."""
    return execute_status_function(
        conn,
        "SELECT success, message FROM asu_schema.f_log_logout()"
    )


def get_login_log(conn, limit=100):
    """Журнал входов/выходов для администратора ИБ."""
    return fetch_all(
        conn,
        "SELECT log_id, db_user, action_name, action_date, success, description FROM asu_schema.f_get_login_log(%s)",
        (limit,)
    )
