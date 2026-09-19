# admin_ops.py
from db_helpers import fetch_all, execute_status_function


def list_users(conn):
    """Список пользователей через функцию БД."""
    return fetch_all(
        conn,
        "SELECT user_id, full_name, login, position_name, role_name, is_active, created_at FROM asu_schema.f_list_users()"
    )


def add_user(conn, full_name, login, password, position_name, role_name, is_active):
    """Добавление или обновление пользователя через функцию БД."""
    return execute_status_function(
        conn,
        "SELECT success, message FROM asu_schema.sp_add_user(%s, %s, %s, %s, %s, %s)",
        (full_name, login, password, position_name, role_name, is_active)
    )


def delete_user(conn, user_id):
    """
    Безопасная блокировка пользователя.
    Имя оставлено для совместимости с прежним интерфейсом.
    """
    return execute_status_function(
        conn,
        "SELECT success, message FROM asu_schema.sp_delete_user(%s)",
        (user_id,)
    )


def get_positions(conn):
    rows = fetch_all(conn, "SELECT position_name FROM asu_schema.f_get_positions()")
    return [r[0] for r in rows]


def get_roles(conn):
    rows = fetch_all(conn, "SELECT role_name FROM asu_schema.f_get_roles()")
    return [r[0] for r in rows]


def set_user_active(conn, user_id, is_active):
    """Блокировка или разблокировка пользователя через функцию БД."""
    return execute_status_function(
        conn,
        "SELECT success, message FROM asu_schema.sp_set_user_active(%s, %s)",
        (user_id, is_active)
    )


def change_user_password(conn, user_id, new_password):
    """Смена пароля пользователя администратором ИС."""
    return execute_status_function(
        conn,
        "SELECT success, message FROM asu_schema.sp_change_user_password(%s, %s)",
        (user_id, new_password)
    )
