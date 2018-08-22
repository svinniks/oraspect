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

    v_session_serial# t_session_serial# := DBMS_DEBUG_JDWP.CURRENT_SESSION_SERIAL;

    TYPE t_message_resolvers IS 
        TABLE OF t_log_message_resolver;
        
    TYPE t_resolver_log_levels IS   
        TABLE OF t_resolver_log_level;    
        
    TYPE t_message_formatters IS
        TABLE OF t_log_message_formatter;
        
    v_message_resolvers t_message_resolvers;
    v_resolver_log_levels t_resolver_log_levels;
    v_message_formatters t_message_formatters;

    v_default_message_formatter t_log_message_formatter;
    
    TYPE t_oracle_error_mappers IS
        TABLE OF t_oracle_error_mapper;
        
    v_oracle_error_mappers t_oracle_error_mappers;
    
    TYPE t_log_message_handlers IS
        TABLE OF t_log_message_handler;
    
    v_message_handlers t_log_message_handlers;
    v_handler_languages t_varchars;
    
    v_default_language STRING;
    v_user_language_mapper t_user_language_mapper;
    
    TYPE t_message_cache IS
        TABLE OF STRING
        INDEX BY STRING;
        
    v_message_cache t_message_cache;
    v_null_language_message STRING;
    
    v_call_id NUMBER(30);    
    v_call_stack t_call_stack;
    
    v_call_values t_call_values;   

    /* Initialization methods */

    PROCEDURE reset IS
    BEGIN
    
        v_message_resolvers := t_message_resolvers();
        v_resolver_log_levels := t_resolver_log_levels();
        
        v_message_formatters := t_message_formatters();
        v_default_message_formatter := NULL;
        
        v_oracle_error_mappers := t_oracle_error_mappers();
        
        v_message_handlers := t_log_message_handlers();
        v_handler_languages := t_varchars();
        
        set_session_log_level(NULL);
        
        v_call_id := 0;
        reset_call_stack;
    
    END;

    PROCEDURE init IS
    BEGIN
    
        reset;
        
        BEGIN
            EXECUTE IMMEDIATE 'BEGIN log$init; END;';
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
        
    END;
    
    /* Resolver and handler management */
    
    PROCEDURE add_message_resolver (
        p_resolver IN t_log_message_resolver,
        p_level IN t_resolver_log_level := c_ALL,
        p_formatter IN t_log_message_formatter := NULL
    ) IS
    BEGIN
    
        IF p_resolver IS NOT NULL THEN
    
            v_message_resolvers.EXTEND(1);
            v_message_resolvers(v_message_resolvers.COUNT) := p_resolver;
            
            v_resolver_log_levels.EXTEND(1);
            v_resolver_log_levels(v_resolver_log_levels.COUNT) := p_level;
            
            v_message_formatters.EXTEND(1);
            v_message_formatters(v_message_formatters.COUNT) := p_formatter;
            
        END IF;
          
    END;
    
    PROCEDURE add_message_resolver (
        p_resolver IN t_log_message_resolver,
        p_formatter IN t_log_message_formatter
    ) IS
    BEGIN
        add_message_resolver(p_resolver, c_ALL, p_formatter); 
    END;
    
    PROCEDURE set_default_message_formatter (
        p_formatter IN t_log_message_formatter
    ) IS
    BEGIN
        v_default_message_formatter := p_formatter;
    END;
    
    PROCEDURE add_message_handler (
        p_handler IN t_log_message_handler,
        p_language IN VARCHAR2 := NULL
    ) IS
    BEGIN
    
        IF p_handler IS NOT NULL THEN
        
            v_message_handlers.EXTEND(1);
            v_message_handlers(v_message_handlers.COUNT) := p_handler;
            
            v_handler_languages.EXTEND(1);
            v_handler_languages(v_handler_languages.COUNT) := p_language;
            
        END IF;
    
    END;
    
    PROCEDURE set_default_language (
        p_language IN VARCHAR2
    ) IS
    BEGIN
        v_default_language := p_language; 
    END;
    
    FUNCTION get_default_language
    RETURN VARCHAR2 IS
    BEGIN
        RETURN v_default_language;
    END;
    
    PROCEDURE add_oracle_error_mapper (
        p_mapper IN t_oracle_error_mapper
    ) IS
    BEGIN
    
        IF p_mapper IS NOT NULL THEN
            v_oracle_error_mappers.EXTEND(1);
            v_oracle_error_mappers(v_oracle_error_mappers.COUNT) := p_mapper;
        END IF;
    
    END;
    
    PROCEDURE set_user_language_mapper (
        p_mapper IN t_user_language_mapper
    ) IS
    BEGIN
        v_user_language_mapper := p_mapper;
    END;
    
    /* System log level management */
    
    FUNCTION get_system_log_level
    RETURN t_handler_log_level IS
    BEGIN
        RETURN SYS_CONTEXT('LOG$LEVELS', 'SYSTEM'); 
    END;
    
    PROCEDURE set_system_log_level (
        p_level IN t_handler_log_level
    ) IS
    BEGIN
        DBMS_SESSION.SET_CONTEXT('LOG$LEVELS', 'SYSTEM', p_level);
    END;       
    
    PROCEDURE init_system_log_level (
        p_level IN t_handler_log_level
    ) IS
         
        v_dummy NUMBER;
        
        CURSOR c_context_variable IS
            SELECT 1
            FROM global_context
            WHERE namespace = 'LOG$LEVELS'
                  AND attribute = 'SYSTEM';
        
    BEGIN
    
        OPEN c_context_variable;
        
        FETCH c_context_variable
        INTO v_dummy;
        
        IF c_context_variable%NOTFOUND THEN
            set_system_log_level(p_level);
        END IF;
        
        CLOSE c_context_variable;
    
    END;
    
    PROCEDURE reset_system_log_level IS
    BEGIN
        DBMS_SESSION.CLEAR_CONTEXT('LOG$LEVELS', NULL, 'SYSTEM');
    END;
        
    FUNCTION get_session_log_level (
        p_session_serial# IN t_session_serial#
    )
    RETURN t_handler_log_level IS
    BEGIN
    
        RETURN SYS_CONTEXT (
            'LOG$LEVELS',
            '#' || p_session_serial#
        );
    
    END;
    
    /* Session log level management */
    
    FUNCTION get_session_log_level
    RETURN t_handler_log_level IS
    BEGIN
        RETURN get_session_log_level(v_session_serial#);
    END;
    
    PROCEDURE cleanup_session_log_levels IS
    
        CURSOR c_non_existing_sessions IS
            SELECT ctx.attribute AS serial#
            FROM global_context ctx,
                 v$session ssn
            WHERE ctx.namespace = 'LOG$LEVELS'
                  AND ctx.attribute LIKE '#%'
                  AND ssn.serial#(+) = SUBSTR(ctx.value, 2)
                  AND ssn.serial# IS NULL;
    
    BEGIN
    
        FOR v_session IN c_non_existing_sessions LOOP
        
            DBMS_SESSION.CLEAR_CONTEXT(
                'LOG$LEVELS',
                NULL,
                v_session.serial#
            );
        
        END LOOP;
    
    END;
    
    PROCEDURE set_session_log_level (
        p_session_serial# IN t_session_serial#,
        p_level IN t_handler_log_level
    ) IS
    BEGIN
    
        cleanup_session_log_levels;
    
        IF p_level IS NULL THEN
            
            DBMS_SESSION.CLEAR_CONTEXT(
                'LOG$LEVELS', 
                NULL,
                '#' || p_session_serial#
            );
            
        ELSE
    
            DBMS_SESSION.SET_CONTEXT(
                'LOG$LEVELS', 
                '#' || p_session_serial#, 
                p_level
            );
            
        END IF;
    
    END;
    
    PROCEDURE set_session_log_level (
        p_level IN t_handler_log_level
    ) IS
    BEGIN
        set_session_log_level(v_session_serial#, p_level);
    END;
    
    /* Call stack management */
    
    FUNCTION call_stack_unit (
        p_depth IN PLS_INTEGER
    )
    RETURN VARCHAR2 IS
        v_unit STRING;
    BEGIN
    
        v_unit := utl_call_stack.owner(p_depth + 1);
        
        IF v_unit IS NULL THEN
            RETURN utl_call_stack.concatenate_subprogram(utl_call_stack.subprogram(p_depth + 1));
        ELSE
            RETURN v_unit || '.' || utl_call_stack.concatenate_subprogram(utl_call_stack.subprogram(p_depth + 1));
        END IF;
    
    END;
    
    PROCEDURE reidentify_untracked_nodes (
        p_matching_depth IN PLS_INTEGER
    ) IS
        
        v_untracked_depth PLS_INTEGER;
    
    BEGIN
    
        v_untracked_depth := 0;
                
        FOR v_i IN REVERSE 1..p_matching_depth LOOP
                
            EXIT WHEN v_call_stack(v_i).first_tracked_line IS NOT NULL;
                    
            v_untracked_depth := v_untracked_depth + 1;
                    
        END LOOP;
                
        FOR v_i IN p_matching_depth - v_untracked_depth + 1..p_matching_depth LOOP
            v_call_id := v_call_id + 1;
            v_call_stack(v_i).id := v_call_id;
        END LOOP; 
    
    END;
    
    PROCEDURE fill_call_stack (
        p_service_depth IN NATURALN,
        p_reset_top IN BOOLEANN,
        p_track_top IN BOOLEANN
    ) IS
    
        v_dynamic_depth PLS_INTEGER;
        v_actual_height PLS_INTEGER;
    
        v_matching_height PLS_INTEGER;
        
        v_depth PLS_INTEGER;
        v_actual_call t_call;
        v_stack_call t_call;
        
    BEGIN
    
        v_matching_height := 0;
    
        v_dynamic_depth := utl_call_stack.dynamic_depth;
        v_actual_height := v_dynamic_depth - p_service_depth - 1; 
        
        FOR v_height IN 1..LEAST(v_call_stack.COUNT, v_actual_height) LOOP
            
            v_depth := v_dynamic_depth - v_height + 1;
        
            v_actual_call.unit := call_stack_unit(v_depth);
            v_actual_call.line := utl_call_stack.unit_line(v_depth);
            
            v_stack_call := v_call_stack(v_height);
            
            IF v_actual_call.unit != v_stack_call.unit THEN
            
                EXIT;
                
            ELSIF v_height = v_actual_height 
                  AND (p_reset_top OR v_actual_call.line <= NVL(v_stack_call.first_tracked_line, v_actual_call.line))
            THEN
            
                EXIT;
                 
            ELSIF v_stack_call.line != v_actual_call.line THEN 
                                   
                v_stack_call.line := v_actual_call.line;
                v_call_stack(v_height) := v_stack_call;
                    
                v_matching_height := v_height;
                EXIT;
                    
            END IF;

            v_matching_height := v_height;
            
        END LOOP;
        
        reidentify_untracked_nodes(v_matching_height);
        
        v_call_stack.TRIM(v_call_stack.COUNT - v_matching_height);
        v_call_values.TRIM(v_call_values.COUNT - v_matching_height);
        
        v_actual_call.first_tracked_line := NULL;
        
        FOR v_height IN v_call_stack.COUNT + 1..v_actual_height LOOP 
        
            v_depth := v_dynamic_depth - v_height + 1;
        
            v_actual_call.unit := call_stack_unit(v_depth);
            v_actual_call.line := utl_call_stack.unit_line(v_depth);
            
            IF v_height = v_actual_height AND p_track_top THEN
                v_actual_call.first_tracked_line := v_actual_call.line;
            END IF;
            
            v_call_id := v_call_id + 1;
            v_actual_call.id := v_call_id;
            
            v_call_stack.EXTEND(1);
            v_call_stack(v_call_stack.COUNT) := v_actual_call;
            
            v_call_values.EXTEND(1);
        
        END LOOP;
    
    END;
    
    PROCEDURE call (
        p_service_depth IN NATURALN := 0
    ) IS
    BEGIN
        fill_call_stack(p_service_depth + 1, TRUE, TRUE);
    END;
    
    PROCEDURE value (
        p_name IN VARCHAR2,
        p_type IN VARCHAR2,
        p_service_depth IN PLS_INTEGER,
        p_fill_call_stack IN BOOLEAN,
        p_varchar2_value IN VARCHAR2 := NULL,
        p_number_value IN NUMBER := NULL,
        p_boolean_value IN BOOLEAN := NULL,
        p_date_value IN DATE := NULL
    ) IS
        v_value t_value;
    BEGIN
    
        IF p_fill_call_stack THEN
        
            fill_call_stack(
                p_service_depth => p_service_depth + 1, 
                p_reset_top => FALSE, 
                p_track_top => TRUE
            );
                
        END IF;
        
        IF v_call_values.COUNT > 0 THEN
        
            v_value.type := p_type;
            v_value.varchar2_value := p_varchar2_value;
            v_value.number_value := p_number_value;
            v_value.boolean_value := p_boolean_value;
            v_value.date_value := p_date_value;
        
            v_call_values(v_call_values.COUNT)(p_name) := v_value;
            
        END IF;
    
    END;
    
    PROCEDURE value (
        p_name IN STRINGN,
        p_value IN VARCHAR2,
        p_service_depth IN NATURALN := 0,
        p_fill_call_stack IN BOOLEANN := TRUE
    ) IS
    BEGIN
    
        value(
            p_name, 
            'VARCHAR2', 
            p_service_depth + 1,
            p_fill_call_stack,
            p_varchar2_value => p_value
        );
    
    END;
    
    PROCEDURE value (
        p_name IN STRINGN,
        p_value IN VARCHAR2,
        p_fill_call_stack IN BOOLEANN
    ) IS
    BEGIN
    
        value(
            p_name, 
            'VARCHAR2', 
            1,
            p_fill_call_stack,
            p_varchar2_value => p_value
        );
    
    END;
    
    PROCEDURE value (
        p_name IN STRINGN,
        p_value IN NUMBER,
        p_service_depth IN NATURALN := 0,
        p_fill_call_stack IN BOOLEANN := TRUE
    ) IS
    BEGIN
    
        value(
            p_name, 
            'NUMBER', 
            p_service_depth + 1,
            p_fill_call_stack,
            p_number_value => p_value
        );
    
    END;
    
    PROCEDURE value (
        p_name IN STRINGN,
        p_value IN NUMBER,
        p_fill_call_stack IN BOOLEANN
    ) IS
    BEGIN
    
        value(
            p_name, 
            'NUMBER', 
            1,
            p_fill_call_stack,
            p_number_value => p_value
        );
    
    END;
    
    PROCEDURE value (
        p_name IN STRINGN,
        p_value IN BOOLEAN,
        p_service_depth IN NATURALN := 0,
        p_fill_call_stack IN BOOLEANN := TRUE
    ) IS
    BEGIN
    
        value(
            p_name, 
            'BOOLEAN', 
            p_service_depth + 1,
            p_fill_call_stack,
            p_boolean_value => p_value
        );
    
    END;
    
    PROCEDURE value (
        p_name IN STRINGN,
        p_value IN BOOLEAN,
        p_fill_call_stack IN BOOLEANN
    ) IS
    BEGIN
    
        value(
            p_name, 
            'BOOLEAN', 
            1,
            p_fill_call_stack,
            p_boolean_value => p_value
        );
    
    END;
    
    PROCEDURE value (
        p_name IN STRINGN,
        p_value IN DATE,
        p_service_depth IN NATURALN := 0,
        p_fill_call_stack IN BOOLEANN := TRUE
    ) IS
    BEGIN
    
        value(
            p_name, 
            'DATE', 
            p_service_depth + 1,
            p_fill_call_stack,
            p_date_value => p_value
        );
    
    END;
    
    PROCEDURE value (
        p_name IN STRINGN,
        p_value IN DATE,
        p_fill_call_stack IN BOOLEANN
    ) IS
    BEGIN
    
        value(
            p_name, 
            'DATE', 
            1,
            p_fill_call_stack,
            p_date_value => p_value
        );
    
    END;
    
    FUNCTION backtrace_unit (
        p_depth IN PLS_INTEGER
    )
    RETURN VARCHAR2 IS
    BEGIN
    
        $IF DBMS_DB_VERSION.VERSION = 12 AND DBMS_DB_VERSION.RELEASE = 1 $THEN
        
            RETURN NVL(utl_call_stack.backtrace_unit(p_depth), '__anonymous_block');
            
        $ELSE

            DECLARE
                e_bad_depth_indicator EXCEPTION;
                PRAGMA EXCEPTION_INIT(e_bad_depth_indicator, -64610);        
            BEGIN
                RETURN utl_call_stack.backtrace_unit(p_depth);
            EXCEPTION
                WHEN e_bad_depth_indicator THEN
                    RETURN '__anonymous_block';
            END;
            
        $END
    
    END;
    
    PROCEDURE do_fill_error_stack (
        p_service_depth IN NATURAL
    ) IS
    
        v_dynamic_depth PLS_INTEGER;
        v_actual_height PLS_INTEGER;
        
        v_matching_height PLS_INTEGER;
        
        v_depth PLS_INTEGER;
        v_actual_call t_call;
        v_stack_call t_call;
        
        v_backtrace_unit VARCHAR2(4000);
        v_backtrace_depth PLS_INTEGER;
        
        v_call t_call;
    
    BEGIN
    
        v_matching_height := 0;
    
        v_dynamic_depth := utl_call_stack.dynamic_depth;
        v_actual_height := v_dynamic_depth - p_service_depth - 1;
    
        FOR v_height IN 1..LEAST(v_call_stack.COUNT, v_actual_height) LOOP
            
            v_depth := v_dynamic_depth - v_height + 1;
        
            v_actual_call.unit := call_stack_unit(v_depth);
            v_actual_call.line := utl_call_stack.unit_line(v_depth);
            
            v_stack_call := v_call_stack(v_height);
            
            EXIT WHEN v_actual_call.unit != v_stack_call.unit
                      OR v_actual_call.line != v_stack_call.line;

            v_matching_height := v_height;
            
        END LOOP;
        
        IF v_matching_height < v_actual_height - 1 THEN
        
            fill_call_stack(
                p_service_depth => p_service_depth + 1,
                p_reset_top => FALSE,
                p_track_top => FALSE
            );    
        
            v_matching_height := v_call_stack.COUNT - 1;
        
        END IF;
        
        $IF DBMS_DB_VERSION.VERSION = 12 AND DBMS_DB_VERSION.RELEASE = 1 $THEN
            v_backtrace_depth := 1;
        $ELSE
            v_backtrace_depth := utl_call_stack.backtrace_depth;
        $END
        
        v_matching_height := v_matching_height + 1;
        
        $IF DBMS_DB_VERSION.VERSION = 12 AND DBMS_DB_VERSION.RELEASE = 1 $THEN
            WHILE v_backtrace_depth <= utl_call_stack.backtrace_depth AND v_matching_height <= v_call_stack.COUNT LOOP
        $ELSE
            WHILE v_backtrace_depth >= 1 AND v_matching_height <= v_call_stack.COUNT LOOP
        $END

            v_backtrace_unit := backtrace_unit(v_backtrace_depth);            
        
            IF v_call_stack(v_matching_height).unit = v_backtrace_unit
               OR v_call_stack(v_matching_height).unit LIKE v_backtrace_unit || '.%' 
            THEN
            
                IF v_call_stack(v_matching_height).line != utl_call_stack.backtrace_line(v_backtrace_depth) THEN
                
                    v_call_stack(v_matching_height).line := utl_call_stack.backtrace_line(v_backtrace_depth);
                
                    $IF DBMS_DB_VERSION.VERSION = 12 AND DBMS_DB_VERSION.RELEASE = 1 $THEN
                        v_backtrace_depth := v_backtrace_depth + 1;
                    $ELSE
                        v_backtrace_depth := v_backtrace_depth - 1;
                    $END
                    
                    v_matching_height := v_matching_height + 1;
                
                    EXIT;
                    
                END IF;
                
            ELSE
            
                EXIT;
                
            END IF;
            
            $IF DBMS_DB_VERSION.VERSION = 12 AND DBMS_DB_VERSION.RELEASE = 1 $THEN
                v_backtrace_depth := v_backtrace_depth + 1;
            $ELSE
                v_backtrace_depth := v_backtrace_depth - 1;
            $END
            
            v_matching_height := v_matching_height + 1;
            
        END LOOP; 
        
        IF v_matching_height <= v_call_stack.COUNT THEN
            v_call_stack.TRIM(v_call_stack.COUNT - v_matching_height + 1);
            v_call_values.TRIM(v_call_values.COUNT - v_matching_height + 1);
        END IF;

        v_call.first_tracked_line := NULL;
        
        $IF DBMS_DB_VERSION.VERSION = 12 AND DBMS_DB_VERSION.RELEASE = 1 $THEN
            WHILE v_backtrace_depth <= utl_call_stack.backtrace_depth LOOP
        $ELSE
            WHILE v_backtrace_depth >= 1 LOOP
        $END
        
            v_backtrace_unit := backtrace_unit(v_backtrace_depth);
            
            v_call_id := v_call_id + 1;
            v_call.id := v_call_id;
            
            v_call.unit := v_backtrace_unit;
            v_call.line := utl_call_stack.backtrace_line(v_backtrace_depth);
            
            v_call_stack.EXTEND(1);
            v_call_stack(v_call_stack.COUNT) := v_call;
            
            v_call_values.EXTEND(1);
            
            $IF DBMS_DB_VERSION.VERSION = 12 AND DBMS_DB_VERSION.RELEASE = 1 $THEN
                v_backtrace_depth := v_backtrace_depth + 1;
            $ELSE
                v_backtrace_depth := v_backtrace_depth - 1;
            $END
        
        END LOOP;
    
    END;
    
    PROCEDURE fill_error_stack (
        p_service_depth IN NATURAL := 0
    ) IS
    BEGIN
        IF utl_call_stack.error_depth > 0 THEN
            do_fill_error_stack(p_service_depth + 1);
        END IF;
    END;
    
    PROCEDURE get_call_stack (
        p_calls OUT t_call_stack,
        p_values OUT t_call_values
    ) IS
    BEGIN
        p_calls := v_call_stack;
        p_values := v_call_values;
    END;
    
    PROCEDURE reset_call_stack IS
    BEGIN
        v_call_stack := t_call_stack();
        v_call_values := t_call_values();
    END;
    
    FUNCTION format_call_stack (
        p_length IN t_string_length := c_STRING_LENGTH,
        p_first_line_indent IN VARCHAR2 := NULL,
        p_indent IN VARCHAR2 := NULL
    )
    RETURN VARCHAR2 IS
    
        v_formatted_call_stack STRING;
        e_length_exceeded EXCEPTION;
        
        v_name STRING;
        
        PROCEDURE put (
            p_text IN VARCHAR2
        ) IS
        BEGIN
        
            IF NVL(LENGTH(v_formatted_call_stack), 0) + NVL(LENGTH(p_text), 0) + 3 > p_length THEN
                v_formatted_call_stack := v_formatted_call_stack || '...';
                RAISE e_length_exceeded;
            END IF;
            
            v_formatted_call_stack := v_formatted_call_stack || p_text;
        
        END;
        
        PROCEDURE put_line (
            p_text IN VARCHAR2 := NULL
        ) IS
        BEGIN
            put(p_text);
            put(CHR(10));
        END;
    
    BEGIN
    
        FOR v_i IN REVERSE 1..v_call_stack.COUNT LOOP

            IF v_i = v_call_stack.COUNT THEN
                put(p_first_line_indent);
            ELSE
                put(p_indent);
            END IF;
                
            put_line(v_call_stack(v_i).unit || ' (line ' || v_call_stack(v_i).line || ')');
                
            v_name := v_call_values(v_i).FIRST;
                
            WHILE v_name IS NOT NULL LOOP
                
                put(p_indent);
                put('    ');
                put(v_name);
                put(': ');
                    
                CASE v_call_values(v_i)(v_name).type
                    
                    WHEN 'VARCHAR2' THEN
                        
                        IF v_call_values(v_i)(v_name).varchar2_value IS NULL THEN
                            put_line('NULL');
                        ELSE
                            put('''');
                            put(REPLACE(v_call_values(v_i)(v_name).varchar2_value, '''', ''''''));
                            put_line('''');
                        END IF;
                            
                    WHEN 'NUMBER' THEN
                        
                        IF v_call_values(v_i)(v_name).number_value IS NULL THEN
                            put_line('NULL');
                        ELSE
                            put_line(TO_CHAR(v_call_values(v_i)(v_name).number_value, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''));
                        END IF;
                            
                    WHEN 'BOOLEAN' THEN
                        
                        IF v_call_values(v_i)(v_name).boolean_value IS NULL THEN
                            put_line('NULL');
                        ELSIF v_call_values(v_i)(v_name).boolean_value IS NULL THEN
                            put_line('TRUE');
                        ELSE
                            put_line('FALSE');
                        END IF;
                            
                    WHEN 'DATE' THEN
                        
                        IF v_call_values(v_i)(v_name).date_value IS NULL THEN
                            put_line('NULL');
                        ELSE
                            put_line('TIMESTAMP ''' || TO_CHAR(v_call_values(v_i)(v_name).date_value, 'YYYY-MM-DD HH24:MI:SS') || '''');
                        END IF;
                        
                    ELSE
                            
                        put_line;
                            
                END CASE;
                
                v_name := v_call_values(v_i).NEXT(v_name);
                
            END LOOP;
            
        END LOOP;
        
        RETURN v_formatted_call_stack;
    
    EXCEPTION
        WHEN e_length_exceeded THEN
            RETURN v_formatted_call_stack;
    END;
    
    /* Generic log message methods */
    
    FUNCTION format_message (
        p_level IN t_message_log_level,
        p_message IN VARCHAR2,
        p_language IN VARCHAR2 := NULL,
        p_arguments IN t_varchars := NULL
    )
    RETURN VARCHAR2 IS
    
        v_message STRING;
        v_formatter t_log_message_formatter;
    
    BEGIN
     
        FOR v_i IN 1..v_message_resolvers.COUNT LOOP
        
            IF p_level >= v_resolver_log_levels(v_i) THEN
            
                v_message := v_message_resolvers(v_i).resolve_message(
                    p_message, 
                    NVL(p_language, v_default_language)
                );
                
                IF v_message IS NOT NULL THEN
                    v_formatter := v_message_formatters(v_i);
                    EXIT;
                END IF;
                
            END IF;
        
        END LOOP;
    
        v_message := NVL(v_message, p_message);
    
        IF v_formatter IS NULL THEN
            v_formatter := v_default_message_formatter;
        END IF;
    
        IF v_formatter IS NOT NULL THEN
        
            v_message := v_formatter.format_message(v_message, p_arguments);
            
        ELSE    
        
            IF p_arguments IS NOT NULL AND p_arguments.COUNT > 0 THEN

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
    
    FUNCTION format_message (
        p_level IN t_message_log_level,
        p_message IN VARCHAR2,
        p_arguments IN t_varchars
    )
    RETURN VARCHAR2 IS
    BEGIN
        RETURN format_message(p_level, p_message, NULL, p_arguments);
    END;

    FUNCTION handling (
        p_level IN t_message_log_level
    )
    RETURN BOOLEAN IS
    BEGIN
    
        FOR v_i IN 1..v_message_handlers.COUNT LOOP
        
            IF p_level >= COALESCE(
                v_message_handlers(v_i).get_log_level, 
                get_session_log_level, 
                get_system_log_level,
                c_NONE
            ) THEN
            
                RETURN TRUE;
                
            END IF;
        
        END LOOP;
    
        RETURN FALSE;
    
    END;
    
    FUNCTION cache_message (
        p_level IN t_message_log_level,
        p_message IN VARCHAR2,
        p_language IN VARCHAR2,
        p_arguments IN t_varchars
    )
    RETURN VARCHAR2 IS
    BEGIN
    
        IF p_language IS NULL THEN
        
            IF v_null_language_message IS NULL THEN
                v_null_language_message := format_message(p_level, p_message, NULL, p_arguments);
            END IF;
            
            RETURN v_null_language_message;
        
        ELSE
        
            IF NOT v_message_cache.EXISTS(p_language) THEN
                v_message_cache(p_language) := format_message(p_level, p_message, p_language, p_arguments);
            END IF;
            
            RETURN v_message_cache(p_language);
        
        END IF;
    
    END;
    
    PROCEDURE reset_message_cache IS
    BEGIN
        v_message_cache.DELETE;
        v_null_language_message := NULL;
    END;
    
    PROCEDURE message (
        p_level IN t_message_log_level,
        p_message IN VARCHAR2,
        p_arguments IN t_varchars := NULL,
        p_service_depth IN NATURALN := 0
    ) IS
    BEGIN
    
        IF handling(p_level) THEN
        
            fill_call_stack(
                p_service_depth => p_service_depth + 1,
                p_reset_top => FALSE,
                p_track_top => TRUE
            );
            
            reset_message_cache;
            
            FOR v_i IN 1..v_message_handlers.COUNT LOOP
        
                IF p_level >= COALESCE(
                    v_message_handlers(v_i).get_log_level, 
                    get_session_log_level, 
                    get_system_log_level,
                    c_NONE
                ) THEN
                
                    v_message_handlers(v_i).handle_message(
                        p_level, 
                        cache_message(
                            p_level, 
                            p_message, 
                            NVL(v_handler_languages(v_i), v_default_language),
                            p_arguments
                        )
                    );
                    
                END IF;
            
            END LOOP;
            
        END IF;
       
    END;
    
    PROCEDURE message (
        p_level IN t_message_log_level,
        p_message IN VARCHAR2,
        p_service_depth IN NATURALN
    ) IS
    BEGIN
        message(p_level, p_message, NULL, p_service_depth + 1);
    END;
    
    PROCEDURE map_oracle_error (
        p_source_code IN NATURALN,
        p_target_code OUT t_target_error_code,
        p_target_message OUT VARCHAR2
    ) IS
    BEGIN
    
        FOR v_i IN 1..v_oracle_error_mappers.COUNT LOOP
        
            v_oracle_error_mappers(v_i).map_oracle_error(p_source_code, p_target_code, p_target_message);
            
            IF p_target_code IS NOT NULL THEN
                RETURN;
            END IF;
        
        END LOOP;
    
    END;
    
    FUNCTION extract_message_arguments (
        p_template IN VARCHAR2,
        p_message IN VARCHAR2,
        p_arguments OUT t_varchars
    )
    RETURN BOOLEAN IS 

        v_position PLS_INTEGER;
        v_placeholder_position PLS_INTEGER;
        
        v_fragments t_varchars;
        v_arguments t_varchars;
        
        FUNCTION find_fragment (
            p_fragment_i IN PLS_INTEGER,
            p_position IN PLS_INTEGER
        )
        RETURN BOOLEAN IS
        
            v_position PLS_INTEGER;
            v_fragment_position PLS_INTEGER;
            
            v_argument_count PLS_INTEGER;
            
        BEGIN
        
            IF p_fragment_i > v_fragments.COUNT THEN
            
                RETURN TRUE;
        
            ELSIF v_fragments(p_fragment_i) = '%s' THEN
                
                IF p_fragment_i = v_fragments.COUNT THEN
                
                    v_arguments.EXTEND(1);
                    v_arguments(v_arguments.COUNT) := SUBSTR(p_message, p_position);
                    
                    RETURN TRUE;
                    
                ELSE
                    RETURN find_fragment(p_fragment_i + 1, p_position);
                END IF;
            
            ELSE
            
                v_argument_count := v_arguments.COUNT;
                v_position := p_position;
                
                WHILE v_position <= LENGTH(p_message) LOOP
                
                    v_fragment_position := INSTR(p_message, v_fragments(p_fragment_i), v_position);
                    
                    IF v_fragment_position = 0 THEN
                        RETURN FALSE;
                    ELSE
                    
                        IF p_fragment_i = 1 THEN
                            IF v_fragment_position > 1 THEN
                                RETURN FALSE;
                            END IF; 
                        ELSE
                            v_arguments.EXTEND(1);
                            v_arguments(v_arguments.COUNT) := SUBSTR(p_message, v_position, v_fragment_position - v_position); 
                        END IF;
                        
                        IF p_fragment_i = v_fragments.COUNT 
                           AND v_fragment_position + LENGTH(v_fragments(p_fragment_i)) <= LENGTH(p_message)
                        THEN
                            RETURN FALSE;
                        END IF;
                        
                        IF find_fragment(p_fragment_i + 1, v_fragment_position + LENGTH(v_fragments(p_fragment_i))) THEN
                            RETURN TRUE;
                        ELSE
                            v_position := v_fragment_position + 1;
                            v_arguments.TRIM(v_arguments.COUNT - v_argument_count);
                        END IF;
                        
                    END IF;
                
                END LOOP;
            
                RETURN FALSE;
                
            END IF;
        
        END;
        
    BEGIN

        IF p_template IS NULL AND p_message IS NOT NULL THEN
            RETURN FALSE;
        END IF;

        v_fragments := t_varchars();
        v_position := 1;
        
        WHILE v_position <= LENGTH(p_template) LOOP
        
            v_placeholder_position := INSTR(p_template, '%s', v_position);
            
            IF v_placeholder_position = 0 THEN
                
                v_fragments.EXTEND(1);
                v_fragments(v_fragments.COUNT) := SUBSTR(p_template, v_position);
                
                EXIT;
        
            ELSE
                
                IF v_placeholder_position > v_position THEN
                    v_fragments.EXTEND(1);
                    v_fragments(v_fragments.COUNT) := SUBSTR(p_template, v_position, v_placeholder_position - v_position);
                ELSIF v_position > 1 THEN
                    RETURN FALSE;
                END IF;
                
                v_fragments.EXTEND(1);
                v_fragments(v_fragments.COUNT) := '%s';
                
                v_position := v_placeholder_position + 2;
            
            END IF;
        
        END LOOP;

        v_arguments := t_varchars();

        IF find_fragment(1, 1) THEN
            p_arguments := v_arguments;
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
            
    END;
    
    FUNCTION translate_oracle_error (
        p_code IN PLS_INTEGER,
        p_message IN VARCHAR2,
        p_language IN VARCHAR2
    )
    RETURN VARCHAR2 IS
    
        v_message_nls_language STRING;
        v_message_template STRING;
        v_message_arguments t_varchars;
        
        v_target_nls_language STRING;
        v_target_template STRING;
        v_target_message STRING;
        
        v_result PLS_INTEGER;
        
    BEGIN
    
        IF p_language IS NULL THEN
        
            v_target_message := NULL;
            
        ELSIF v_message_cache.EXISTS(p_language) THEN
        
            v_target_message := v_message_cache(p_language);
            
        ELSE
        
            IF v_user_language_mapper IS NULL THEN
                v_target_nls_language := p_language;
            ELSE
                v_target_nls_language := v_user_language_mapper.to_nls_language(p_language);
            END IF;
            
            IF v_target_nls_language IS NOT NULL THEN
            
                SELECT value
                INTO v_message_nls_language
                FROM nls_session_parameters
                WHERE parameter = 'NLS_LANGUAGE';
            
                IF v_target_nls_language != v_message_nls_language
                   AND utl_lms.get_message(p_code, 'RDBMS', 'ORA', v_message_nls_language, v_message_template) = 0
                   AND extract_message_arguments(v_message_template, p_message, v_message_arguments) 
                   AND utl_lms.get_message(p_code, 'RDBMS', 'ORA', v_target_nls_language, v_target_template) = 0 
                THEN   
                    
                    v_target_message := v_target_template;
                    
                    FOR v_i IN 1..v_message_arguments.COUNT LOOP
                        v_target_message := REGEXP_REPLACE(v_target_message, '\%s', v_message_arguments(v_i), 1, 1);
                    END LOOP;
                    
                END IF;
            
            END IF;
        
        END IF;
    
        RETURN 'ORA-' || LPAD(p_code, 5, '0') || ': ' || NVL(v_target_message, p_message);
    
    END;
    
    PROCEDURE oracle_error (
        p_level IN t_message_log_level,
        p_service_depth IN NATURALN,
        p_mapped_code OUT t_target_error_code,
        p_mapped_message OUT VARCHAR2
    ) IS
    
        v_code PLS_INTEGER;
        v_message STRING;
        
    BEGIN
    
        IF utl_call_stack.error_depth > 0 AND handling(p_level) THEN 
    
            do_fill_error_stack(p_service_depth + 1);
        
            v_code := utl_call_stack.error_number(1);
            v_message := utl_call_stack.error_msg(1);
            
            $IF DBMS_DB_VERSION.VERSION = 12 AND DBMS_DB_VERSION.RELEASE = 1 $THEN
                v_message := SUBSTR(v_message, 1, LENGTH(v_message) - 1);
            $END
            
            map_oracle_error(v_code, p_mapped_code, p_mapped_message);
            
            IF p_mapped_code IS NOT NULL THEN
            
                message(
                    p_level,
                    p_mapped_message,
                    t_varchars(v_code, v_message),
                    p_service_depth + 1
                );
             
            ELSE
            
                reset_message_cache;
                                
                FOR v_i IN 1..v_message_handlers.COUNT LOOP
        
                    IF p_level >= COALESCE(
                        v_message_handlers(v_i).get_log_level, 
                        get_session_log_level, 
                        get_system_log_level,
                        c_NONE
                    ) THEN
                    
                        v_message_handlers(v_i).handle_message(
                            p_level,
                            translate_oracle_error(
                                v_code,
                                v_message,
                                NVL(v_handler_languages(v_i), v_default_language)
                            )
                        );
                        
                    END IF;
                
                END LOOP;
                
            END IF;     
 
        END IF;
    
    END;
    
    PROCEDURE oracle_error (
        p_level IN t_message_log_level := c_FATAL,
        p_service_depth IN NATURALN := 0
    ) IS
    
        v_mapped_code t_target_error_code;
        v_mapped_message STRING;
    
    BEGIN
        oracle_error(p_level, p_service_depth + 1, v_mapped_code, v_mapped_message);
    END;
    
    /* Shortcut message methods */
        
    PROCEDURE debug (
        p_message IN VARCHAR2,
        p_arguments IN t_varchars := NULL
    ) IS
    BEGIN
    
        message(c_DEBUG, p_message, p_arguments, 1);
        
    END;
    
    PROCEDURE debug (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_DEBUG,
            p_message, 
            t_varchars(p_argument_1),
            1
        );
    
    END;
    
    PROCEDURE debug (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_DEBUG,
            p_message, 
            t_varchars(p_argument_1, p_argument_2),
            1
        );
    
    END;
    
    PROCEDURE debug (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_DEBUG,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3),
            1
        );
    
    END;
    
    PROCEDURE debug (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_DEBUG,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4),
            1
        );
    
    END;
    
    PROCEDURE debug (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2,
        p_argument_5 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_DEBUG,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4, p_argument_5),
            1
        );
    
    END;
        
    PROCEDURE info (
        p_message IN VARCHAR2,
        p_arguments IN t_varchars := NULL
    ) IS
    BEGIN
    
        message(c_INFO, p_message, p_arguments, 1);
        
    END; 
    
    PROCEDURE info (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_INFO,
            p_message, 
            t_varchars(p_argument_1),
            1
        );
    
    END;
    
    PROCEDURE info (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_INFO,
            p_message, 
            t_varchars(p_argument_1, p_argument_2),
            1
        );
    
    END;
    
    PROCEDURE info (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_INFO,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3),
            1
        );
    
    END;
    
    PROCEDURE info (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_INFO,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4),
            1
        );
    
    END;
    
    PROCEDURE info (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2,
        p_argument_5 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_INFO,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4, p_argument_5),
            1
        );
    
    END;
    
    PROCEDURE warning (
        p_message IN VARCHAR2,
        p_arguments IN t_varchars := NULL
    ) IS
    BEGIN
    
        message(c_WARNING, p_message, p_arguments, 1);
        
    END;
    
    PROCEDURE warning (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_WARNING,
            p_message, 
            t_varchars(p_argument_1),
            1
        );
    
    END;
    
    PROCEDURE warning (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_WARNING,
            p_message, 
            t_varchars(p_argument_1, p_argument_2),
            1
        );
    
    END;
    
    PROCEDURE warning (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_WARNING,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3),
            1
        );
    
    END;
    
    PROCEDURE warning (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_WARNING,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4),
            1
        );
    
    END;
    
    PROCEDURE warning (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2,
        p_argument_5 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_WARNING,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4, p_argument_5),
            1
        );
    
    END;
        
    PROCEDURE error (
        p_message IN VARCHAR2,
        p_arguments IN t_varchars := NULL
    ) IS
    BEGIN
    
        message(c_ERROR, p_message, p_arguments, 1);
        
    END;
    
    PROCEDURE error (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_ERROR,
            p_message, 
            t_varchars(p_argument_1),
            1
        );
    
    END;
    
    PROCEDURE error (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_ERROR,
            p_message, 
            t_varchars(p_argument_1, p_argument_2),
            1
        );
    
    END;
    
    PROCEDURE error (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_ERROR,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3),
            1
        );
    
    END;
    
    PROCEDURE error (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_ERROR,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4),
            1
        );
    
    END;
    
    PROCEDURE error (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2,
        p_argument_5 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_ERROR,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4, p_argument_5),
            1
        );
    
    END;
    
    PROCEDURE fatal (
        p_message IN VARCHAR2,
        p_arguments IN t_varchars := NULL
    ) IS
    BEGIN
    
        message(c_FATAL, p_message, p_arguments, 1);
        
    END;
    
    PROCEDURE fatal (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_FATAL,
            p_message, 
            t_varchars(p_argument_1),
            1
        );
    
    END;
    
    PROCEDURE fatal (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_FATAL,
            p_message, 
            t_varchars(p_argument_1, p_argument_2),
            1
        );
    
    END;
    
    PROCEDURE fatal (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_FATAL,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3),
            1
        );
    
    END;
    
    PROCEDURE fatal (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_FATAL,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4),
            1
        );
    
    END;
    
    PROCEDURE fatal (
        p_message IN VARCHAR2,
        p_argument_1 IN VARCHAR2,
        p_argument_2 IN VARCHAR2,
        p_argument_3 IN VARCHAR2,
        p_argument_4 IN VARCHAR2,
        p_argument_5 IN VARCHAR2
    ) IS
    BEGIN
    
        message(
            c_FATAL,
            p_message, 
            t_varchars(p_argument_1, p_argument_2, p_argument_3, p_argument_4, p_argument_5),
            1
        );
    
    END;
    
BEGIN

    init;    
    
END;

