-- Server/role/database settings that a migration must not change (tamper evidence).
SELECT 'role|' || rolname || '|super=' || rolsuper || '|createrole=' || rolcreaterole FROM pg_roles WHERE rolname IN ('migrator','app','analytics') ORDER BY 1;
SELECT 'dbrole_setting|' || coalesce(d.datname,'*') || '|' || coalesce(r.rolname,'*') || '|' || array_to_string(s.setconfig, ',')
  FROM pg_db_role_setting s LEFT JOIN pg_database d ON d.oid = s.setdatabase LEFT JOIN pg_roles r ON r.oid = s.setrole
  WHERE r.rolname IS DISTINCT FROM 'migrator' ORDER BY 1;
SELECT 'file_setting|' || name || '=' || setting FROM pg_file_settings WHERE sourcefile LIKE '%auto.conf' ORDER BY 1;
