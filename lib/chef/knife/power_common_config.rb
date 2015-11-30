#
# Copyright:: Copyright (c) 2014 Chef Software Inc.
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
    module PowerCommonConfig
      def getmanagedsys()
        if config[:debug]
          ui.info "Getting list of managed sys on HMC #{config[:hmc]}"
        end
        array_hosts = Array.new
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          command = "lssyscfg -r sys -F name,state | grep Operating | cut -d\",\" -f 1"
          output = run_remote_command(ssh, command)
          if output =~ /HSCL8/
            ui.error "Error running the command"
            output.split("\n").first(2).each do |x|
              ui.error x
              exit 1
            end
            ui.error "..."
          end
          array_hosts = output.split("\n")
        end
        if config[:debug]
          ui.info "Managed Hosts :"
          array_hosts.each do |sys|
            ui.info "\t=>#{sys},"
          end
        end
        return array_hosts
      end

      def getlparlist(managedhost)
        array_lpars = Array.new
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          command = "lssyscfg -r lpar -m #{managedhost} -F name,curr_profile,lpar_env | grep -v vioserver | cut -d\",\" -f 1"
          output = run_remote_command(ssh, command)
          if output =~ /HSCL8/
            ui.error "Error running the command"
            output.split("\n").first(2).each do |x|
              ui.error x
              exit 1
            end
            ui.error "..."
          end
          array_lpars = output.split("\n")
        end
        return array_lpars
      end

      def getlparconfig(managedhost,lpar)
        hash_profile = Hash.new(Array.new)
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          ###
          ### We will form :
          ###    {"MANAGED_HOST"=> [{"lpar_name" => "abc123", with all other key values...
          ###                        :profiles => [{profile1}, {profile2}]
          ###                        }]}
          ### Fetch lpar info
          command = "lssyscfg -r lpar -m #{managedhost} --filter \"lpar_names=#{lpar}\""
          output = run_remote_command(ssh, command)
          if output =~ /HSCL8/
            ui.error "Error running the command"
            output.split("\n").first(2).each do |x|
              ui.error x
              exit 1
            end
            ui.error "..."
          end
          ## parsing (key=value)
          lparinfo = parse_profile(output.chomp)
          lparinfo[:profiles] = Array.new
          ### Fetching profiles for parition
          command = "lssyscfg -r prof -m #{managedhost} --filter \"lpar_names=#{lpar}\" | sed -e \"s/\\\"/'/g\" -e \"s/,/;/g\""
          output = run_remote_command(ssh, command)
          if output =~ /HSCL8/
            ui.error "Error running the command"
            output.split("\n").first(2).each do |x|
              ui.error x
              exit 1
            end
            ui.error "..."
          end
          ## For each profiles, parsing & adding to array
          output.gsub!("'","\"")
          output.gsub!(";",",")
          output.split("\n").each do |line|
            profile = parse_profile(line)
            lparinfo[:profiles].insert(-1, profile)
          end
          hash_profile[managedhost] = Array.new
          hash_profile[managedhost].insert(-1, lparinfo)
        end
        return hash_profile
      end

    end
  end
end
