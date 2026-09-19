# auth.py
from getpass import getpass
from db_helpers import fetch_one, AppDatabaseError


def get_current_user_info(conn):
    """
    Получает сведения о текущем пользователе через функцию БД.
    Базовые таблицы users/roles напрямую не запрашиваются.
    """
    if not conn:
        return None
    row = fetch_one(conn, "SELECT login, full_name, role_name FROM asu_schema.f_get_my_role() LIMIT 1")
    if not row:
        return None
    return {
        'login': row[0],
        'full_name': row[1],
        'role_name': row[2]
    }


def get_role(conn):
    try:
        info = get_current_user_info(conn)
        if not info:
            return None
        return info.get('role_name')
    except AppDatabaseError:
        return None


if __name__ == "__main__":
    from db_connection import get_connection, close_connection
    login = input("Логин: ")
    pwd = getpass("Пароль: ")
    conn = get_connection(login, pwd)
    if conn:
        info = get_current_user_info(conn)
        if info:
            print("Пользователь: {}".format(info.get('full_name')))
            print("Роль: {}".format(info.get('role_name')))
        else:
            print("Роль не определена.")
        close_connection(conn)
    else:
        print("Подключение не установлено.")
