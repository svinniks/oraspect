# Summary

PL-LOG introduces a set of APIs to enable PL/SQL code instrumentation with log messages of different levels (e.g. DEBUG, INFO, ERROR etc.), custom business error raising and unexpected Oracle error handling. 
Log and error messages can be codified, translated into different languages, stored in arbitrary locations and later loaded by pluggable message __resolvers__. Both codified and free-text messages may act as template strings with argument placeholders, which are later replaced with actual values using pluggable __formatters__.

All formatted messages are finally directed to (also pluggable) __handlers__ which store or forward them according to the user and developer needs. Each handler can be configured to process messages in a different language - this can be useful, for example, in a multi-language user environment to store all log entries only in english, but to display messages to the users in their preferred language.

PL-LOG can be configured with unlimited number or message resolvers/formatters/handlers, limiting flow of the messages with log level constraints. Log level of messages being handled can be manipulated irrespective of database transactions on the __system__, __session__ (even different from the current one!) and __handler__ level which allows developers to leave even the finest level logger calls (DEBUG and lower) in the code and quickly enable message output when necessary.

Additional useful features include __call stack tracking__ with subprogram __argument and variable value logging__, ORA- error __translating__ and __mapping__ to custom business errors upon reraise, custom language code handling.

PL-LOG is based on the [`UTL_CALL_STACK`](https://docs.oracle.com/database/121/ARPLS/u_call_stack.htm#ARPLS74078]) package and therefore is only available on Oracle 12c R1 and up. Oracle abstract [object types](https://docs.oracle.com/database/121/ADOBJ/adobjint.htm#ADOBJ00101) are used to implement extensible plugin API, so getting familiar with the OOP concepts is advisable before using the framework.

Below is a short example of how some PL-LOG using looks like:

```
CREATE OR REPLACE 
PROCEDURE owner.register_person (
    p_name IN VARCHAR2,
    p_birth_date IN DATE
BEGIN

    -- Help PL-LOG to track the call stack and 
    -- associate argument values with the current call.
    log$.call()
        .param('p_name', p_name)
        .param('p_birth_date', p_birth_date);
        
    -- Log beginning of the person registration routine
    log$.debug('Registering of a person started.');
    
    -- Check if P_NAME has been supplied and raise a codified business error if not.
    IF p_name IS NULL THEN
        -- :1 is not specified!
        error$.raise('MSG-00001', 'name');
    END IF;

END;

-- Call the procedure from an anonymous block:
BEGIN
    register_person(NULL, SYSDATE);
END;
```

Providing that `DBMS_OUTPUT` handler is enabled and configured to accept all level messages, the following exception will be raised:

```
ORA-20000: MSG-00001: name is not specified!
```

and the following lines will be fetched from `DBMS_OUTPUT`:

```
23:57:48.268 [DEBUG  ] Registering of a person started.
23:57:48.268 [ERROR  ] MSG-00001: name is not specified!
at: OWNER.REGISTER_PERSON (line 19)
        p_birth_date: TIMESTAMP '2018-08-23 23:57:48'
        p_name: NULL
    __anonymous_block (line 2)
```
# Prerequisites

- PL-LOG only supports Oracle database 12c Release 1 and higher as it uses the ```UTL_CALL_STACK``` package, which first appeared in 12c R1.
- It is advisable to install PL-LOG in a separate schema to avoid object naming conflicts. The user must at least have the following privileges:

    ```
    CREATE USER pllog IDENTIFIED BY "password"
    /

    GRANT 
        CONNECT,
        CREATE SEQUENCE,
        CREATE TABLE,
        UNLIMITED TABLESPACE,
        CREATE PROCEDURE,
        CREATE VIEW,
        CREATE ANY CONTEXT,
        DROP ANY CONTEXT,
        CREATE TYPE
    TO pllog
    /

    GRANT SELECT ON v$session TO pllog
    /
    ```
- [PL-COMMONS](https://github.com/svinniks/pl-commons) must be installed as PL-LOG depends on the ```T_VARCHARS``` type. The type must be installed either in the same schema as PL-LOG itself, or it must be made accessible to the PL-LOG user via a synonym. Note however, that you will need to access ```T_VARCHARS``` from your code in order to pass argument lists to the message formatting routines.

# Installation

To install PL-LOG, connect to the database as the desired user/schema and run ```install.sql```.
After installation you may want to make PL-LOG API accessible to other users. At the very minimum you should: 

```
GRANT EXECUTE ON log$ TO <PUBLIC|any_separate_user_or_role>
/
GRANT EXECUTE ON error$ TO <PUBLIC|any_separate_user_or_role>
/
```

It is also recommended to create __public synonyms__ for these objects to keep call statements as short as possible. Please refer to the next chapters to get familiar with other PL-LOG objects which it is usable to grant public access to.

# Architecture

## Log levels

Each log message must be supplemented with a numeric __log level__, which denotes severity (importance) of the message. PL-LOG supports up to 600 log levels expressed in positive integers ranged from 1 to 600. There are five predefined log levels ```DEBUG = 100```, ```INFO = 200```, ```WARNING = 300```, ```ERROR = 400``` and ```FATAL = 500```.

Users can set __theshold log level__ on the __system__, __session__ and __handler__ level to control how many messages are getting handled (persisted). For example, if your code contains a lot of ```DEBUG``` level messages, you would not want to always store them all in the log table to save disk space and to increase performance. In that case ```INFO``` can be set as the threshold value for the whole system so that only messages with level 200 or more would get "noticed" and handled. However, if the system starts to behave incorrectly, operators can instantly swith the threshold to ```ALL = 0``` and start observing the log table while trying to reproduce the invalid behavior.

Threshold log level for each message handler gets resolved as ```COALESCE(handler_log_level, session_log_level, system_log_level)``` which means that the session level overrides the system one and the handler level overrides both session and system level thresholds. If all three threshold levels are ```NULL```, then messages __won't be handled__ at all.

## Message handlers

By default, PL-LOG only provides the API to issue log messages of different levels. These messages, however, are not stored or displayed anywhere. To persist or show messages, PL-LOG must be configured to include one or more __message handlers__. Handlers may store messages in a table, file system, alert log or a trace file, output them to ```DBMS_OUTPUT``` or send via e-mail. It is possible to develop custom message handlers and plug them into PL-LOG without recompiling the framework's source code. 

Message handler API is implemented via an abstract object type ```T_LOG_MESSAGE_HANDLER```:

```
CREATE OR REPLACE TYPE t_log_message_handler IS OBJECT (

    dummy CHAR,
        
    NOT INSTANTIABLE MEMBER FUNCTION get_log_level
    RETURN PLS_INTEGER,
    
    NOT INSTANTIABLE MEMBER PROCEDURE handle_message (
        p_level IN PLS_INTEGER,
        p_message IN VARCHAR2
    )
    
) 
NOT INSTANTIABLE NOT FINAL
```

The field ```dummy``` is there only because Oracle doesn't allow to create object types without fields.

While creating custom message handlers, developer must extend ```T_LOG_MESSAGE_HANDLER``` and implement two methods: ```GET_LOG_LEVEL``` and ```HANDLE_MESSAGE```.

```GET_LOG_LEVEL``` must return threshold log level of the handler. PL-LOG will call the method while deciding whether to call the handler's ```HANDLE_MESSAGE``` method or not. It's up to the developer to decide where the return value for ```GET_LOG_LEVEL``` comes from. It may be a simple session-wide package global variable or a system-wide global value stored in a globally accessed context.

```HANDLE_MESSAGE``` is called by PL-LOG when the message passes the level threshold and should be persisted. The message text passed is already __translated and formatted__, so the handler must just save, display or forward it.

Please refer to the [```CREATE TYPE```](https://docs.oracle.com/database/121/LNPLS/create_type.htm) documentation to get familiar with how object type inheritance works in Oracle.

Message handlers must be added to PL-LOG by the [configuration procedure]() discussed later.

### Built-in message handlers

There are two message handlers PL-LOG comes bundled with:

- ```T_DEFAULT_MESSAGE_HANDLER```
- ```T_DBMS_OUTPUT_HANDLER```

```T_DEFAULT_MESSAGE_HANDLER``` appends log messages to a circular buffer based on a collection variable stored in the handler implementation package ```DEFAULT_MESSAGE_HANDLER```. 

- Messages can be observed by selecting from the ```LOG$TAIL``` view. Only the messages of the current session are visible to the user.

- Size of the buffer can be changed by calling ```DEFAULT_MESSAGE_HANDLER.SET_CAPACITY```.

- Log level threshold of the default message handler is set via ```DEFAULT_MESSAGE_HANDLER.SET_LOG_LEVEL``` and works only in context of the session.

```T_DBMS_OUTPUT_HANDLER``` writes log messages to ```DBMS_OUTPUT```. Just like for the default message handler, there is an implementation package called ```DBMS_OUTPUT_HANDLER```.

- Log level threshold can be changed by calling ```DBMS_OUTPUT_HANDLER.SET_LOG_LEVEL``` (also only for the current session).
- By default the handler will output callstack for all messages with level 400 (```ERROR```) or higher. To lower or to raise call stack display level threshold call ```DBMS_OUTPUT_HANDLER.SET_CALL_STACK_LEVEL```.
- While displaying the call stack, tracked subprogram argument values will by default be displayed using colon as a separator:

    ```
    23:57:48.268 [ERROR  ] MSG-00001: name is not specified!
    at: OWNER.REGISTER_PERSON (line 19)
            p_birth_date: TIMESTAMP '2018-08-23 23:57:48'
            p_name: NULL
        __anonymous_block (line 2)
    ```

    It is possible, however, to make ```DBMS_OUTPUT_HANDLER``` display parameters using PL/SQL named notation, by issuing ```DBMS_OUTPUT_HANDLER.SET_ARGUMENT_NOTATION(TRUE)```:
    ```
    23:57:48.268 [ERROR  ] MSG-00001: name is not specified!
    at: OWNER.REGISTER_PERSON (line 19)
            p_birth_date => TIMESTAMP '2018-08-23 23:57:48',
            p_name => NULL
        __anonymous_block (line 2)
    ```

    This feature can be useful to ease rerunning failed subprogram by just copy-pasting the argument values into your PL/SQL IDE. 
    
    Please note that argument values as displayed as valid __PL/SQL literals__ for ```VARCHAR2```, ```NUMBER```, ```DATE```, ```BOOLEAN``` and compatible type arguments.

## Message resolvers

It is a common practice to codify all the messages in the system, especially those which are displayed to the end users. Codifying means assigning each message a unique code and storing the texts somwhere outside the PL/SQL code, for example in a table. This approach enables multi-language message support, eases reusing and sistematizaion of the system's messages.

In PL-LOG, external message store concept is implemented via __message resolvers__ and the ```T_LOG_MESSAGE_RESOLVER`` abstract object type:

```
CREATE OR REPLACE TYPE t_log_message_resolver IS OBJECT (

    dummy CHAR,

    NOT INSTANTIABLE MEMBER FUNCTION resolve_message (
        p_message IN VARCHAR2,
        p_language IN VARCHAR2 := NULL
    )
    RETURN VARCHAR2
    
) NOT INSTANTIABLE NOT FINAL
```

The only method that needs to be implemented in a custom resolver is ```RESOLVE_MESSAGE```. The method is given a ```P_MESSAGE``` to resolve and an optional ```P_LANGUAGE```. If language is not specified then it's up to the resolver implementation to decide which language to return the resolved message in (one of the options can be the default system language, another is to use current session ```NLS_LANGUAGE```). ```P_MESSAGE``` format is also not strictly defined. While integrating PL-LOG into an existing system developers might want to implement a resolver based on the existing message definition table.

If the message has been successfully resolved, then the text must be returned from the function. Please note, that PL-LOG __will not add the original message__ code to the resolved text. For example, if there is a message with the code ```'MSG-00001'``` which resolves to the text ```'Invalid value!'```, the resolver might consider to concatenate them together before returning: ```'MSG-00001: Invalid value!'```.

If the message could not be resolved, ```NULL``` must be returned from ```RESOLVE_MESSAGE```. PL-LOG allows to define multiple resolvers. These resolvers will be called by the framework in the same order they have been registered. The firts one which returns a non-NULL value will "win", so no other resolver will be called.

In case the message could not be resolved by any of the registered resolvers, the original text will be passed to the handlers.

### Built-in resolvers

PL-LOG comes bundled with one message resolver ```T_DEFAULT_MESSAGE_RESOLVER```, which is based on an associative array package variable and does not support multi-language messages. However, it can be useful if you are planning to create a reusable package which is message store agnostic and comes bundled with all the messages it is using. Consider the following example:

```
CREATE POR REPLACE PACKAGE a_very_useful_package IS
    /* Subprogram declarations */
    ...
END;

CREATE POR REPLACE PACKAGE BODY a_very_useful_package IS
    
    PROCEDURE register_messages I
    BEGIN
        default_message_handler.register_message('MSG-00001', 'Not all parameters have been filled correctly!');
        default_message_handler.register_message('MSG-00002', 'Insufficient privileges to run :1!');
    END;

    /* Subprogram implementations */
    ...

BEGIN
    register_messages;
END;
```

```REGISTER_MESSAGES``` is called from the initialization block of ```A_VERY_USEFUL_PACKAGE``` and registers all the necessary messages by issuing ```DEFAULT_MESSAGE_HANDLER.REGISTER_MESSAGE```.

## Message formatters

Formatting is the process of replacing special placeholders in a message text with the provided values. This feature allows to define log messages not only as constant strings, but also as templates, which are later filled with data to provide end users more detailed information of what has happened in the system. 

PL-LOG doesn't define any specific message template format, instead it provides an abstract object type called ```T_LOG_MESSAGE_FORMATTER``` which implements the formatter concept:

```
CREATE OR REPLACE TYPE t_log_message_formatter IS OBJECT (

    dummy CHAR,
        
    NOT INSTANTIABLE MEMBER FUNCTION format_message (
        p_message IN VARCHAR2,
        p_arguments IN t_varchars
    )
    RETURN VARCHAR2
    
) 
NOT INSTANTIABLE NOT FINAL
```

Single method ```FORMAT_MESSAGE``` must be implemented to create a custom message formatter. The method accepts a template string and an array of ```VARCHAR2``` argument values and must return a fully formatted message text.

There is one message formatter included in PL-LOG by default, which is called ```T_DEFAULT_MESSAGE_FORMATTER```. It allows to include sequential numbers of arguments as value placeholders, prefixed with at most one special character. For example, if a developer chooses to use colon ```':'``` as the prefix, valid message templates would look like:

```
User :1 has no privileges to run service :2!
File :1 could not be found!
```

The prefix character can be defined while constructing a ```T_DEFAULT_MESSAGE_FORMATTER``` instance:

```
t_default_message_formatter(':');
```
# Public API

PL-LOG public API consists of two packages: ```LOG$``` and ```ERROR$```. 

```LOG$``` provides methods for log message formatting and dispatching, call stack and subprogram argument tracking, unexpected Oracle error handling, threshold log level manipulation and PL-LOG framework configuration. Constants for the predefined log levels are also defined in the ```LOG$``` package.

```ERROR$``` is used for both free-text and codified businness error raising and Oracle build-in error reraising after handling. The package ensures that any error will be forwarded to the handlers for storing only once.

## Configuration

All PL-LOG configuration, namely message resolvers, formatters, handlers and log level thresholds, is stored in ```LOG$``` package variables, is local to the session and therefore must be initialized upon session creation. The default entry point for configuring PL-LOG is a special schema-level procedure called ```LOG$INIT```. ```LOG$``` will try to run this procedure from it's initialization block dynamically, using ```EXECUTE IMMEDIATE```. Procedure must either reside in the same schema as PL-LOG does or to be resolvable via a synonym.



## Instrumentation

## Exception handling