CREATE OR REPLACE PROCEDURE log$init IS
BEGIN

    log$.init_system_log_level(log$.C_INFO);
    
    log$.add_message_resolver(t_default_message_resolver());
    
    log$.add_message_handler(t_default_message_handler(), 'ENG');
    log$.add_message_handler(t_dbms_output_handler(), 'ENG');
    
    log$.set_default_message_formatter(t_default_message_formatter(':'));
    
    log$.set_user_language_mapper(t_iso_language_mapper());
    
END;