#
# Author:: Vianney Foucault (<vianney.foucault@gmail.com>)
# Copyright:: Copyright (c) 2015 The Author
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'io/console'
require 'net/ssh'
require 'json'

class Chef
  class Knife
    module PowerCreateSchema

      def getschema

        json_schema = {"type"=>"object",
 "required"=>["managedsys", "lparname", "vp", "mem", "ame"],
 "properties"=>
  {"managedsys"=>{"type"=>"string"},
   "lparname"=>{"type"=>"string"},
   "vp"=>{"type"=>"integer"},
   "mem"=>{"type"=>"integer"},
   "ame"=>{"type"=>"number"},
   "ldevs"=>
    {"type"=>"array",
     "items"=>{"type"=>"string"},
     "minItems"=>1,
     "uniqueItems"=>true},
   "vdevs"=>
    {"type"=>"object",
     "required"=>["vnet"],
     "properties"=>
      {"vscsi"=>
        {"type"=>"object",
         "required"=>["vio1", "vio2"],
         "properties"=>
          {"vio1"=>
            {"type"=>"array",
             "items"=>{"type"=>"integer"},
             "minItems"=>1,
             "uniqueItems"=>true},
           "vio2"=>
            {"type"=>"array",
             "items"=>{"type"=>"integer"},
             "minItems"=>1,
             "uniqueItems"=>true}}},
       "vfc"=>
        {"type"=>"object",
         "required"=>["vio1", "vio2"],
         "properties"=>
          {"vio1"=>
            {"type"=>"array",
             "items"=>{"type"=>["integer", "string"]},
             "minItems"=>2,
             "uniqueItems"=>true},
           "vio2"=>
            {"type"=>"array",
             "items"=>{"type"=>["integer", "string"]},
             "minItems"=>2,
             "uniqueItems"=>true}}},
       "vnet"=>
        {"type"=>"array",
         "items"=>{"type"=>"integer"},
         "minItems"=>1,
         "uniqueItems"=>true}}},
   "netboot"=>
    {"type"=>"object",
     "required"=>["vlan", "ip", "netmask", "gateway"],
     "properties"=>
      {"vlan"=>{"type"=>"integer"},
       "ip"=>{"type"=>"string"},
       "netmask"=>{"type"=>"string"},
       "gateway"=>{"type"=>"string"}}}}}

        return json_schema
      end
    end
  end
end

