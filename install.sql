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

SET DEFINE OFF

@@tables/log$events.tab
/

@@types/t_log_message_formatter.tps
/
@@types/t_log_message_resolver.tps
/
@@types/t_log_message_handler.tps
/
@@types/t_user_language_mapper.tps
/

@@types/t_top_call.tps
/
@@packages/log$.pks
/

@@types/t_top_call.tpb
/
@@packages/log$.pkb
/

@@packages/error$.pks
/
@@packages/error$.pkb
/

@@packages/default_message_resolver.pks
/
@@packages/default_message_resolver.pkb
/

@@types/t_default_message_resolver.tps
/
@@types/t_default_message_resolver.tpb
/

@@packages/default_message_handler.pks
/
@@packages/default_message_handler.pkb
/

@@types/t_default_message_handler.tps
/
@@types/t_default_message_handler.tpb
/

@@packages/dbms_output_handler.pks
/
@@packages/dbms_output_handler.pkb
/

@@types/t_dbms_output_handler.tps
/
@@types/t_dbms_output_handler.tpb
/

@@types/t_default_message_formatter.tps
/
@@types/t_default_message_formatter.tpb
/

@@tables/iso_language_map.tab
/
@@data/iso_language_map.sql

@@types/t_iso_language_mapper.tps
/
@@types/t_iso_language_mapper.tpb
/

@@views/log$tail.vw
/

@@contexts/log$levels.ctx
/

@@synonyms/public_synonyms.sql
