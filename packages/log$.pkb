CREATE OR REPLACE PACKAGE BODY log$ IS

    /* 
        Copyright 2017 Sergejs Vinniks

        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at
     
          http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.
    */

    TYPE t_message_resolvers IS TABLE OF t_log_message_resolver;
    v_message_resolvers t_message_resolvers;
    
    TYPE t_message_handlers IS TABLE OF t_log_message_handler;
    v_message_handlers t_message_handlers;
    
    v_session_log_level PLS_INTEGER;

    PROCEDURE init IS
    BEGIN
    
        v_message_resolvers := t_message_resolvers();
        v_message_handlers := t_message_handlers();
        
        BEGIN
        
            EXECUTE IMMEDIATE 'BEGIN log$_init; END;';
        
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    
    END;
    
    PROCEDURE add_message_resolver
        (p_message_resolver IN t_log_message_resolver) IS
    BEGIN
    
        v_message_resolvers.EXTEND(1);
        v_message_resolvers(v_message_resolvers.COUNT) := p_message_resolver;
          
    END;
    
    PROCEDURE add_message_handler
        (p_message_handler IN t_log_message_handler) IS
    BEGIN
    
        v_message_handlers.EXTEND(1);
        v_message_handlers(v_message_handlers.COUNT) := p_message_handler;
    
    END;
    
    FUNCTION resolve_message
        (p_code IN VARCHAR2)
    RETURN VARCHAR2 IS
    
        v_message VARCHAR2(32000);
    
    BEGIN
     
        FOR v_i IN 1..v_message_resolvers.COUNT LOOP
        
            v_message := v_message_resolvers(v_i).resolve_message(p_code);
            
            IF v_message IS NOT NULL THEN
                RETURN v_message;
            END IF;
        
        END LOOP;
    
        RETURN NULL;
        
    END;

    FUNCTION format_message
        (p_message IN VARCHAR2
        ,p_arguments IN t_varchars := NULL)
    RETURN VARCHAR2 IS
    
        v_message VARCHAR2(4000);
        
    BEGIN
    
        -- First try to resolve the message as a code.
        v_message := resolve_message(p_message);
        
        -- If the message could be resolved and there are arguments, then replace 
        -- the placeholders for with the values:
        IF v_message IS NOT NULL THEN
        
            IF p_arguments IS NOT NULL THEN
        
                FOR v_i IN 1..p_arguments.COUNT LOOP
                     v_message := REPLACE(v_message, ':' || v_i, p_arguments(v_i));
                END LOOP;
            
            END IF;
            
            v_message := p_message || ': ' || v_message;
            
        -- If the message could not be resolved from the code, then the message 
        -- itself will be output followed by the arguments, if provided, in brackets.
        ELSE
        
            v_message := p_message;
            
            IF p_arguments IS NOT NULL THEN
            
                IF v_message IS NOT NULL THEN
                    v_message := v_message || ' (';
                ELSE
                    v_message := v_message || '(';
                END IF;
                
                FOR v_i IN 1..p_arguments.COUNT LOOP
                
                    IF v_i > 1 THEN
                        v_message := v_message || ', ';
                    END IF;
                
                    v_message := v_message || p_arguments(v_i);
                   
                END LOOP;
                
                v_message := v_message || ')';
            
            END IF;
        
        END IF;
        
        RETURN v_message;
    
    END;
    
    FUNCTION format_message
        (p_message IN VARCHAR2
        ,p_argument1 IN VARCHAR2)
    RETURN VARCHAR2 IS
    BEGIN
    
        RETURN format_message(p_message, t_varchars(p_argument1));
        
    END;
    
    FUNCTION format_message
        (p_message IN VARCHAR2
        ,p_argument1 IN VARCHAR2
        ,p_argument2 IN VARCHAR2)
    RETURN VARCHAR2 IS
    BEGIN
    
        RETURN format_message(p_message, t_varchars(p_argument1, p_argument2));
        
    END;
    
    FUNCTION format_message
        (p_message IN VARCHAR2
        ,p_argument1 IN VARCHAR2
        ,p_argument2 IN VARCHAR2
        ,p_argument3 IN VARCHAR2)
    RETURN VARCHAR2 IS
    BEGIN
    
        RETURN format_message(p_message, t_varchars(p_argument1, p_argument2, p_argument3));
        
    END;
    
    FUNCTION format_message
        (p_message IN VARCHAR2
        ,p_argument1 IN VARCHAR2
        ,p_argument2 IN VARCHAR2
        ,p_argument3 IN VARCHAR2
        ,p_argument4 IN VARCHAR2)
    RETURN VARCHAR2 IS
    BEGIN
    
        RETURN format_message(p_message, t_varchars(p_argument1, p_argument2, p_argument3, p_argument4));
        
    END;
    
    FUNCTION format_message
        (p_message IN VARCHAR2
        ,p_argument1 IN VARCHAR2
        ,p_argument2 IN VARCHAR2
        ,p_argument3 IN VARCHAR2
        ,p_argument4 IN VARCHAR2
        ,p_argument5 IN VARCHAR2)
    RETURN VARCHAR2 IS
    BEGIN
    
        RETURN format_message(p_message, t_varchars(p_argument1, p_argument2, p_argument3, p_argument4, p_argument5));
        
    END;
    
    PROCEDURE message
        (p_level IN PLS_INTEGER
        ,p_message IN VARCHAR2
        ,p_arguments IN t_varchars := NULL) IS
        
        v_message VARCHAR2(4000);
        v_message_formatted BOOLEAN;
        
    BEGIN
    
        v_message_formatted := FALSE;
        
        FOR v_i IN 1..v_message_handlers.COUNT LOOP
        
            IF p_level >= COALESCE(v_message_handlers(v_i).get_log_level, get_session_log_level, get_system_log_level) THEN
            
                IF NOT v_message_formatted THEN
                    v_message := format_message(p_message, p_arguments);
                    v_message_formatted := TRUE;
                END IF;
              
                v_message_handlers(v_i).handle_message(p_level, p_message, NULL);
                
            END IF;
        
        END LOOP;
    
    END;
        
    PROCEDURE debug
        (p_message IN VARCHAR2
        ,p_arguments IN t_varchars := NULL) IS
    BEGIN
    
        message(c_debug, p_message, p_arguments);
        
    END;
        
    PROCEDURE info
        (p_message IN VARCHAR2
        ,p_arguments IN t_varchars := NULL) IS
    BEGIN
    
        message(c_info, p_message, p_arguments);
        
    END; 
        
    PROCEDURE warning
        (p_message IN VARCHAR2
        ,p_arguments IN t_varchars := NULL) IS
    BEGIN
    
        message(c_warning, p_message, p_arguments);
        
    END;
        
    PROCEDURE error
        (p_message IN VARCHAR2
        ,p_arguments IN t_varchars := NULL) IS
    BEGIN
    
        message(c_error, p_message, p_arguments);
        
    END;
    
    FUNCTION get_system_log_level
    RETURN PLS_INTEGER IS
    BEGIN
    
        RETURN SYS_CONTEXT('log$context', 'log_level'); 
    
    END;
    
    PROCEDURE set_system_log_level
        (p_level IN PLS_INTEGER) IS
    BEGIN
    
        DBMS_SESSION.SET_CONTEXT('log$context', 'log_level', p_level);
    
    END;       
    
    PROCEDURE init_system_log_level
        (p_level IN PLS_INTEGER) IS
         
        v_dummy NUMBER;
        
        CURSOR c_context_variable IS
            SELECT 1
            FROM global_context
            WHERE namespace = 'LOG$CONTEXT'
                  AND attribute = 'LOG_LEVEL';
        
    BEGIN
    
        OPEN c_context_variable;
        
        FETCH c_context_variable
        INTO v_dummy;
        
        IF c_context_variable%NOTFOUND THEN
            set_system_log_level(p_level);
        END IF;
        
        CLOSE c_context_variable;
    
    END;
        
    FUNCTION get_session_log_level
    RETURN PLS_INTEGER IS
    BEGIN
    
        RETURN v_session_log_level;
    
    END;
    
    PROCEDURE set_session_log_level
        (p_level IN PLS_INTEGER) IS
    BEGIN
    
        v_session_log_level := p_level;
    
    END;
    
BEGIN

    init;    
    
END;

