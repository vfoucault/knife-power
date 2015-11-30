#
# Author:: Vianney Foucault (<vianney.foucault@gmail.com>)
# Copyright:: Copyright (c) 2015
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
require 'chef/knife/power_common_config'
require 'chef/knife/power_create_schema'
require 'ruby-progressbar'

class Chef
  class Knife
    class PowerLparNetboot < Knife
      include Chef::Knife::PowerCommon
      include Chef::Knife::PowerCreateSchema
      ###
      ### Get hosting system for a lpar
      ###
      banner "knife power lpar install [options]"

      option :configfile,
        :short => "-C configfile",
        :long => "--config-file configfile",
        :description => "optional configuration to use"

      option :hmc,
        :short => "-h HMC",
        :long => "--hmc HMC",
        :description => "Hardware Management Console"

      option :ssh_port,
        :short => "-p SSH_PORT",
        :long => "--ssh-port SSH_PORT",
        :description => "Change the default SSH Port",
        :default => 22

      option :hmc_user,
        :short => "-U HMC_USER",
        :long => "--hmc-user HMC_USER",
        :description => "HMC user",
        :default => "hscroot"

      option :prompt_password,
        :short => "-P passwd",
        :long => "--hmc-passwd passwd",
        :description => "Prompt for the hmc user's password"

      option :partition,
        :short => "-n PARTITION",
        :long => "--partition PARTITION",
        :description => "Partition Name"

      option :json_config_file,
        :short => "-e jsonfile",
        :long => "--json-config jsonfile",
        :description => "Source Json configuration file"

      option :debug,
        :short => "-D",
        :long => "--debug",
        :description => "Debug mode"

      #
      # Run the plugin
      #

      def run
        #### First, check if a configuration is present and if we can load vars from it
        configfile = loadConfig(config[:configfile])
        if configfile
          ### configuration file prensent, loading data
          config[:hmc] = configfile[:hmc][:host]
          config[:ssh_port] = configfile[:hmc][:port]
          config[:hmc_user] = configfile[:hmc][:user]
          config[:prompt_password] = configfile[:hmc][:password]
          config[:nimserver] = configfile[:nim][:host]
          config[:nimport] = configfile[:nim][:port]
          config[:nimuser] = configfile[:nim][:user]
          config[:nimpasswd] = configfile[:nim][:password]
          if configfile[:nim][:nimobjects]
            config[:nimobjects] = configfile[:nim][:nimobjects]
          end
        end
        check_params
        @input_data = validate_config_file
        ###
        create_nim_client
        create_nim_job
        lpar_netboot
      end

      def check_params
        if config[:hmc].nil?
          ui.error "No HMC parameter specified"
          show_usage
          exit 1
        end
        if not config[:prompt_password].nil?
          if config[:prompt_password] == ""
            @hmc_passwd = prompt_hmc_passwd
          else
            @hmc_passwd = config[:prompt_password]
          end
        end
      end

      def isnimclient?(hostname)
        ### check if hostname is yet a nim client
        Net::SSH.start(config[:nimserver], config[:nimuser], {:password => config[:nimpasswd],:port => config[:nimport]}) do |ssh|
          command = "lsnim #{hostname} 2>&1"
          output = run_remote_command(ssh,command)
          if output.match(/0042-053 lsnim: there is no NIM object name/)
	    return false
          else
            return true
          end
        end
      end

      def create_nim_client
        Net::SSH.start(config[:nimserver], config[:nimuser], {:password => config[:nimpasswd],:port => config[:nimport]}) do |ssh|
          lparname = @input_data["lparname"]
          unless isnimclient?(lparname)
            command = "nim -o define -t standalone -a platform=chrp -a if1=\"find_net #{lparname} 0\" -a cable_type1=tp -a net_settings1=\"auto auto\" -a netboot_kernel=64 #{lparname}"
            output = run_remote_command(ssh,command)
          end
        end
      end

      def check_nimclientstate(nimclient)
        Net::SSH.start(config[:nimserver], config[:nimuser], {:password => config[:nimpasswd],:port => config[:nimport]}) do |ssh|
          command = "lsnim -l #{nimclient}"
          output = run_remote_command(ssh,command)
          if output.match(/control\s+=\s#{nimclient}\spush_off/)
            return "clientcontrol"
          elsif output.match(/Cstate\s+=\sready\sfor\sa\sNIM\soperation/) 
            return "ok"
          else
            return "nok"
          end
        end
      end

      def create_nim_job
        Net::SSH.start(config[:nimserver], config[:nimuser], {:password => config[:nimpasswd],:port => config[:nimport]}) do |ssh|
          lparname   = @input_data["lparname"]
          clientstatus = check_nimclientstate(lparname)
          if clientstatus == "ok"
            sysrefname = @input_data["netboot"]["sysref"].scan(/\w+_(\w+)/)[0][0]
            command    = "odmget -q \"name like \*#{sysrefname}\" nim_object"
            output     = run_remote_command(ssh,command)
            lppname    = output.scan(/\s+\w+\s=\ "(\w+)"\n\s+\w+\s=\s\w+\n\s+(?=type = "33")/).flatten[0]
            mksysbname = output.scan(/\s+\w+\s=\ "(\w+)"\n\s+\w+\s=\s\w+\n\s+(?=type = "39")/).flatten[0]
            spotname   = output.scan(/\s+\w+\s=\ "(\w+)"\n\s+\w+\s=\s\w+\n\s+(?=type = "24")/).flatten[0]
            addtl_objects = ""
            if config[:nimobjects]
              config[:nimobjects].each do |obj|
                addtl_objects << "-a #{obj} "
              end
            end
            command    = "nim -o bos_inst -a source=mksysb -a mksysb=#{mksysbname} #{addtl_objects} -a accept_licenses=yes -a installp_flags=-acNgXY -a no_client_boot=yes -a preserve_res=yes #{lparname}"
            output     = run_remote_command(ssh,command)
          elsif clientstatus == "clientcontrol"
            ui.error "Machine #{lparname} is currently under client control. Issue 'nimclient -p' on the client to update this."
            exit 1
          else
            ui.error "Unknown error. Check both nim server & client."
            exit 1
          end
        end
      end

      def lpar_netboot
        ### not matter what, we will netboot on the first configured interface
        lparname = @input_data["lparname"]
        managedsys = @input_data["managedsys"]
        ## if the lpar is up, we can't proceed
        lparstate = get_lparstatus(managedsys,lparname)
        if not lparstate == "Not Activated"
          ui.error "The lpar #{lparname} is currently running."
          ui.error "Power it off to proceed"
          exit 1
        end
        profilename = "default" ## the default name for a new partition
        clientip = @input_data["netboot"]["ip"]
        netmask = @input_data["netboot"]["netmask"]
        gateway = @input_data["netboot"]["gateway"]
        ## interface number to boot with, setting ip/mask/gateway & server
        ## temporary workaround :
        command = "lpar_netboot -f -T off -t ent -s auto -d auto -D -K #{netmask} -G #{gateway} -S #{config[:nimserver]} -C #{clientip} #{lparname} #{profilename} #{managedsys}"
        progressbar = ProgressBar.create(:smoothing => 0.6, :length => 100, :title => "lpar netboot", :format => '%a |%b>>%i| %p%% %t', :starting_at => 0, :total => 100, :autofinish => true)
        myundefinedcounter = 0
        thrupdatethebar = Thread.new { until myundefinedcounter == 100; progressbar.refresh; sleep 1; end }
        execlparnetboot(command,progressbar)
        command = "rmvterm -m #{managedsys} -p #{lparname}; mkvterm -m #{managedsys} -p #{lparname}"
        monitorinstall(command,progressbar)
        ui.info "#{ui.color("[Success]", :green)} End of installation process"
        ui.info "Allow some time for system customization"
      end

      def monitorinstall(command,progressbar)
        ssh = Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]})
        progressbar.title = "TFTP Copy"
        ssh.exec!(command) do |mych,stream,data|
          if data.match(/Welcome to AIX/)
            progressbar.title = "Installation in progress..."
            10.times{ progressbar.increment }
          elsif data.match(/\s+\d+\s+\d+\s+([\S+\ ]*)/)
            datalog = data.scan(/\s+\d+\s+\d+\s+([\S+\ ]*)$/).flatten[0]
            log = datalog.scan(/[[:print:]]+/)
            progressbar.title log
            2.times { progressbar.increment }
          elsif data.match(/Rebooting/)
            progressbar.finish
            break
          end
        end
      end

      def execlparnetboot(command,progressbar)
        ssh = Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]})
        progressbar.refresh
        2.times { progressbar.increment }
        ssh.exec!(command) do |mychannel,stream,data|
	  progressbar.log "debug => #{data}"
	  if data.match(/ping unsuccessful/)
	    progressbar.stop
	    ui.error "Unable to ping bootserver from client. Check network settings"
	    exit 1
	  end
          if data.match(/lpar_netboot is exiting/)
            progressbar.progress = 5
            break
          end
        end
      end

      def findlpar(lparname)
        mangedsys = getmanagedsys
        mangedsys.each do |sys|
          lparlist = getlparlist(sys)
          if lparlist.include? lparname
            return sys
          end
        end
      end

    end
  end
end

