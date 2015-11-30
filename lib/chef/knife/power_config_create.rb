#
# Author:: Vianney Foucault (<vianney.foucault@gmail.com>)
# Copyright:: Copyright (c) 2015:: The Author
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
require 'chef/knife'
require 'chef/knife/power_common'
require 'chef/knife/power_create_schema'
require 'highline/import'
require 'rubygems'
require 'json-schema'
require 'pp'
require 'json'
require 'ip'

class Chef
  class Knife
    class PowerConfigCreate < Knife
      include Chef::Knife::PowerCommon
      include Chef::Knife::PowerCreateSchema
      ###
      ### Set of tools to lpar configuration
      ### => used to get hdisk : vio : adapter : vscsi mappings
      ###
      banner "knife power config create [options]"

      option :configfile,
        :short => "-C configfile",
        :long => "--config-file configfile",
        :description => "optional configuration to use"

      option :json_config_file,
        :short => "-e jsonfile",
        :long => "--json-config jsonfile",
        :description => "Source Json configuration file"

      option :debug,
        :long => "--debug",
        :description => "set the debug flag",
        :default => false


      ## let's roll
      def run
	initsettings()
        configfile = loadConfig(config[:configfile])
        config[:nimserver] = configfile[:nim][:host]
        config[:nimuser] = configfile[:nim][:user]
        config[:nimpasswd] = configfile[:nim][:password]
        config[:nimport] = configfile[:nim][:port]
        check_params
        lparconfig = prep_config_file
        if configfile[:misc][:configdir] && Dir.exists?(File.expand_path(configfile[:misc][:configdir]))
          filename = File.expand_path(configfile[:misc][:configdir]) + "/" + lparconfig["lparname"] + ".json"
          savejson(lparconfig,filename)
        end
      end

      def check_params
        if config[:hmc].nil?
          ui.error "No HMC parameter specified"
          show_usage
          exit 1
        end
      end

      def setupldevs()
        text = "Ldev devices to use in order : rootvg,softvg,othervg"
        line = "-" * text.length
        say("<%= color('#{text}', :headline) %>")
        say("<%= color('#{line}', :horizontal_line) %>")
        say("<%= color('enter them in the following form : ARRAYSN:LDEVID;ARRAYSN:LDEVID (eg.: 15EF5:0256;15EF5:02A8)', BOLD) %>")
        mylist = ask("LDEVs to use : ") { |q| q.case = :up }
        arrayldev = mylist.scan(/(\w{5}:\w{4})/)
        puts "\n Entered ldevs list :"
        arrayldev.flatten.each do |entry|
          puts "=> #{entry}"
        end
        choose do |menu|
          menu.index_suffix = " - "
          menu.prompt = "Is the input correct ?"
          menu.choice :yes do return arrayldev.flatten end
          menu.choice :no do setupldevs end
        end
      end

      def prep_config_file
	myhmc = PowerVMTools::HMC.new(config[:hmc],{ :user => config[:hmc_user], :passwd => config[:hmcpasswd], :port => config[:ssh_port],:debug => config[:debug] })
	@mynim = PowerVMTools::NIM.new(config[:nimserver],{:user => config[:nimuser], :passwd => config[:nimpasswd],:port => config[:port]})
	
        ### formating highline
        ft = HighLine::ColorScheme.new do |cs|
         cs[:headline]        = [ :bold, :yellow, :on_black ]
         cs[:header]        = [ :bold, :yellow, :on_black ]
         cs[:horizontal_line] = [ :bold, :white ]
         cs[:even_row]        = [ :green ]
         cs[:odd_row]         = [ :magenta ]
        end

        HighLine.color_scheme = ft
        text = "LPAR Json configuration creator"
        line = "-" * text.length
        say("<%= color('#{text}', :headline) %>")
        say("<%= color('#{line}', :horizontal_line) %>")

        hash_response = { 'managedsys' => '',
                          'lparname' => '',
                          'vp' => 0,
                          'mem' => 0,
                          'ame' => 1.2,
                          'vdevs' => Hash.new
                          }
        managedsystems = myhmc.framesbystatus("Operating")

        text = "Managed systems available on this HMC"
        line = "-" * text.length
        say("<%= color('#{text}', :headline) %>")
        say("<%= color('#{line}', :horizontal_line) %>")
        choose do |menu|
          menu.index        = :letter
          menu.index_suffix = " - "
          menu.prompt = "Please choose the hosting managed system : "
          managedsystems.each do |sys|
            menu.choice sys.to_sym do hash_response["managedsys"] = sys end
          end
        end
        puts ""
        text = "LPAR Settings :"
        line = "-" * text.length
        say("<%= color('#{text}', :headline) %>")
        say("<%= color('#{line}', :horizontal_line) %>")
        hash_response["lparname"] = ask("LPAR Name ? ") { |q| q.validate = /\S{4,16}/ ; q.case = :down}
        hash_response["vp"] = ask("Number of Virtual processors ? ") { |q| q.validate = /\d{1}/ ; q.answer_type = Integer }
        hash_response["mem"] = ask("Quantity of Memory (Gb) ? ") { |q| q.validate = /\d{1,3}/; q.answer_type = Integer }
        say("<%= color('#{line}', :horizontal_line) %>")
        choose do |menu|
          menu.index        = :letter
          menu.index_suffix = " - "
          menu.prompt = 'Use VSCSI Adapters ? '
          menu.choice :yes do hash_response["vdevs"]["vscsi"] = { "vio1" =>  [20,22], "vio2" => [21,23] }; hash_response['ldevs'] = setupldevs() end
          menu.choice :no do end
        end
        say("<%= color('#{line}', :horizontal_line) %>")
        choose do |menu|
          menu.index        = :letter
          menu.index_suffix = " - "
          menu.prompt = 'Use VFC Adapters ? '
          menu.choice :yes do hash_response["vdevs"]["vfc"] = { "vio1" => [30,"fcs0"], "vio2" => [31,"fcs3"] } end
          menu.choice :no do end
        end

        text = "Networks :"
        line = "-" * text.length
        say("<%= color('#{text}', :headline) %>")
        say("<%= color('#{line}', :horizontal_line) %>")
        hash_response["vdevs"]["vnet"] = Array.new
        nbslan = ask('How much network interface to create ? ') { |q| q.validate = /[1-4]/; q.answer_type = Integer }
        counter = 1
        while nbslan > 0
          vlan = ask("VLAN ID for interface no. #{counter}? ") { |q| q.validate = /\d{1,4}/; q.answer_type = Integer }
          hash_response["vdevs"]["vnet"].insert(-1,vlan)
          counter += 1
          nbslan -= 1
        end

        text = "NetBoot :"
        line = "-" * text.length
        say("<%= color('#{text}', :headline) %>")
        say("<%= color('#{line}', :horizontal_line) %>")
        choose do |menu|
          menu.index        = :letter
          menu.index_suffix = " - "
          menu.prompt = 'Setup IP for netboot ? : '
          menu.choice :yes do hash_response["netboot"] = choose_inet_netboot(hash_response["vdevs"]["vnet"]) end
          menu.choice :no do end
        end

        text = "Sysref :"
        line = "-" * text.length
        say("<%= color('#{text}', :headline) %>")
        say("<%= color('#{line}', :horizontal_line) %>")
	sysreflist = @mynim.spots.map { |x| a = x[:spotname].sub("SPOT_",""); if not a.match(/IOS/); a; end}.flatten.compact.sort { |x,y| y <=> x }
        choose do |menu|
          menu.index        = :letter
          menu.index_suffix = " - "
          menu.prompt = 'Which Sysref to use ? : '
	  sysreflist.each do |sysref|
	    menu.choice sysref.sub("LPP_","").to_sym do hash_response["netboot"]["sysref"] = sysref.sub("LPP_",'') end
	  end
        end
        return hash_response
      end

      def choose_inet_netboot(arrayvnet)
        res = ""
        if arrayvnet.length == 1
          res = prompt_ip_netboot(arrayvnet[0])
        else
          choose do |menu|
            menu.index        = :letter
            menu.index_suffix = " - "
            menu.prompt = 'Which Vlan to use for netboot : '
            arrayvnet.each do |vnet|
              menu.choice vnet do res = prompt_ip_netboot(vnet) end
            end
          end
        end
        return res
      end

      def prompt_ip_netboot(vnet)
        nimnetworks = @mynim.networks
        ip = ask("IP for netboot for vnet #{vnet} ? ") { |q| q.validate = /^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9]{1,2})(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9]{1,2})){3}$/}
        netmask = ask("Netmask for IP #{ip} ? ") { |q| q.validate = /^(((0|128|192|224|240|248|252|254).0.0.0)|(255.(0|128|192|224|240|248|252|254).0.0)|(255.255.(0|128|192|224|240|248|252|254).0)|(255.255.255.(0|128|192|224|240|248|252|254)))$/}
        ### for get the prefix length, let's create a nex IP object with the netmask
        ### then the prerix length will be the binary representation, counting 1's
        ### finally, myip will be the IP/Prefix
        cidr = IP.new(netmask)
        pfxlen = cidr.to_b.to_s.count("1")
        myip = IP.new(ip + "/" + pfxlen.to_s)
        ### to get the network without the prefix, let's split '/XX'
        netipsearch,prefix = myip.network.to_s.split('/')
        netmasksearch = myip.netmask.to_s
        ### see if some already defined nim network match our inputs
        nimnet = nimnetworks.select{ |x| x[:network] == netipsearch && x[:netmask] == netmasksearch  }
        gateway = ""
        if nimnet.length > 0
          ## if there is a match
          gateway = nimnet[0][:gateway]
          nimnetname = nimnet[0][:netname]
        else
          ### otherwise, prompt for the missing gateway info 
          gateway = ask("gateway for IP #{ip} ? ") { |q| q.validate = /^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9]{1,2})(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9]{1,2})){3}$/}
          mygateway = IP.new(gateway)
          if not mygateway.is_in?(myip.network)
            ui.error "the gateway #{gateway} is not in the same network as #{ip}/#{pfxlen}. Try again"
            prompt_ip_netboot(vnet)
          end
	  nimnetname = "N/A"
        end
	hash_return = { "vlan" => vnet, "ip" => ip, "netmask" => netmask, "gateway" => gateway, "nimnetname" => nimnetname }
        return hash_return
      end
      ###
    end
  end
end


