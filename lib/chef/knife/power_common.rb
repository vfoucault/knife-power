#
# Author:: Vianney Foucault (<vianney.foucault@gmail.com>)
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
require 'yaml'

class Chef
  class Knife
    module PowerCommon
      
      def initsettings
        #### First, check if a configuration is present and if we can load vars from it
	filename = File.expand_path(config[:configfile])
        configfile = loadConfig(filename)
        if configfile
          ### configuration file prensent, loading data
	  ui.info "Loading configuration file #{config[:configfile]}"
          config[:hmc] = configfile[:hmc][:host]
          config[:ssh_port] = configfile[:hmc][:port]
          config[:hmc_user] = configfile[:hmc][:user]
          config[:hmcpasswd] = configfile[:hmc][:password]
	  @friendlynames = configfile[:friendlynames]
        else
          ui.error "Unable to load configuration file."
          exit 1
        end
        if config[:hmc].nil?
          ui.error "No HMC parameter specified in configuration file"
          exit 1
        end
      end

      def loadConfig(configfile)
        if File.exists?(configfile)
          config = YAML.load_file(configfile)
        else
          return false
        end
        return config
      end

      def loadjson(file)
        ##
        ## Load json file and return a hash of the json file
        ##
        json = File.read(file)
        hash = JSON.parse(json)
        return hash
      end

      def savejson(hash,file)
        File.open(file,"w") do |f|
          f.write(hash.to_json)
        end
        if File.exists?(file)
          ui.info "#{ui.color("Successfully", :green)} saved file #{file}"
        else
          ui.error "Something went wrong saving file #{file}"
        end
      end

      def get_lparstatus(managedsys,lparname)
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          command = "lssyscfg -r lpar -m #{managedsys} --filter lpar_names=#{lparname} -F state"
          output = run_remote_command(ssh, command).chomp()
          if output =~ /HSCL/
            ui.error "Error running the command"
            output.split("\n").first(2).each do |x|
              ui.error x
              exit 1
            end
            ui.error "..."
          end
	  return output
        end
      end


      def save_lpar_current_config(managedsys,lparid)
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          command = "mksyscfg -r prof -m #{managedsys} -o save --id #{lparid} -n $(lssyscfg -r lpar -m #{managedsys} --filter \\\"lpar_ids=#{lparid}\\\" -F curr_profile) --force"
          puts "command => #{command}"
          output = run_remote_command(ssh, command)
          if output =~ /HSCL/
            ui.error "Error running the command"
            output.split("\n").first(2).each do |x|
              ui.error x
              exit 1
            end
            ui.error "..."
          end
        end
      end

      def prompt_hmc_passwd
        print "Enter #{config[:hmc_user]} password for HMC: "
        STDIN.noecho(&:gets).chomp
      end

      def run_remote_command(ssh, command)
        return_val = String.new
        ssh.exec! command do |ch, stream, data|
          if stream == :stdout
            return_val << data.chomp
          else
            # some exception is in order I think
            ui.error "Something went wrong:"
            ui.error data.to_s
            exit 1
          end
        end
        return return_val
      end

      def parse_profile(data)
        ### parse the output of the profile listing command
        ### return a hash of the profile key=value
        profile = Hash.new
        ### Frist of all, let's clean and remove all the \n inside the string :
        data.gsub!("\n","") if data =~ /\n/
        ### Ok, a bit tricky here. Since the formating of virtual_fc_adapters contains more commas, it's treated with the scan as another matching group
        ### So, first we must transform the input to
        ###     => match the WWN1 & WWN2 and replace the separting comma with a slash
        ###     => gsub to remove the "","" (sperating fc_adapters entries) with a simple comma
        ###     => Finaly, remove all the ""
        data.gsub!(/(\h{16}),(\h{16})/,'\1' + "/" + '\2').gsub!("\"\",\"\"",",").gsub!("\"\"","") if data =~ /(\h{16})/
        parameters = data.scan( /([^",]+)|"([^"]+)"/ ).flatten.compact
        parameters.each do |param|
          tmparray = param.split("=")
          key = tmparray[0]
          value = tmparray[1]
          profile[key] = value
        end
        return profile
      end

      def fetch_vio_vadapter(managed_sys,vio_id,adap_id)
        ## return the vhost adapter name (eg: vhost5) from the VIOS
        ## take the managedsys as input as well as the VIOSid and the adapter ID
        ### the VIOs command will return :
        ### "U9117.MMA.65E3503-V159-C148  Virtual I/O Slot  vhost28"
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          command = "viosvrcmd -m #{managed_sys} --id #{vio_id} -c \"lsdev -slots\" | grep \"V#{vio_id}-C#{adap_id}\ \""  ## running the viosvrcmd to get the vscsi adapter name
          vscsiname = run_remote_command(ssh, command)
          return vscsiname.split[-1]
        end
      end

      def fetch_vio_fcmap(managed_sys,vio_id,vfchost)
        hash_mapping = Hash.new
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          command = "viosvrcmd -m #{managed_sys} --id #{vio_id} -c \"lsmap -vadapter #{vfchost} -npiv -fmt ':'\""
          mapping = run_remote_command(ssh, command)
          if not mapping.nil?
            fcmap = mapping.split(":")
            ## vfchost0:U9117.MMD.XXXXXXX-V1-C7:15:lpar1:AIX:LOGGED_IN:fcs0:U2C4E.001.DBY0000-P2-C4-T1:1:a:fcs0:U9117.MMD.XXXXXXX-V15-C30
            status =  fcmap[5]
            fcname =  fcmap[6]
            physloc = fcmap[7]
            portsli = fcmap[8]
            flags =   fcmap[9]
            clntfcname = fcmap[10]
            hash_mapping = {"status" => status,
                            "fcname" => fcname,
                            "physloc" => physloc,
                            "portstatus" => portsli,
                            "flags" => flags,
                            "clntfcname" => clntfcname}
          end
        end
        return hash_mapping
      end

      def validate_config_file
        begin
          print "%-50s" % "Opening file #{config[:json_config_file]}"
          jsondata = ::File.open(config[:json_config_file])
          print_ok
          hash_data = JSON.parse(jsondata.read)
          ## Check all mandatory Fields
          ## let setup a json schema :
          schema = getschema
          print "%-50s" % "Validating JSON Schema"
          JSON::Validator.validate!(schema, hash_data)
          print_ok
          return hash_data
        rescue JSON::Schema::ValidationError
          print_ko
          ui.error "Configuration file #{config[:json_config_file]} does not have a valide schema!"
          raise $!.message
        rescue JSON::ParserError => e
          print_ko
          ui.error "Configuration file #{config[:json_config_file]} structure is invalid!"
          raise "Error with json structure"
        ensure
          jsondata.close unless jsondata.nil?
        end
      end
      
      def commonids(array1,array2)
        ### Let's find the two first common consecutive number inside two array as input
        ### Need sorted Array as input, but just in case, we resort them
        ## let's convert every single item into an integer just in case
        array1.map!(&:to_i)
        array2.map!(&:to_i)
        ## Add a max ids inside both array to be sure to have a result
        #array1.insert(-1, array1.sort[-1]+10)
        #array2.insert(-1, array2.sort[-1]+10)
        ## let's create a new array based on the differences between the input array and another array witch is made from the minimum value to the max value in the input array
        newarray1 = (array1.sort[0]...array1.sort[-1]).to_a - array1.sort
        newarray2 = (array2.sort[0]...array2.sort[-1]).to_a - array2.sort
        ## let's now intersect the two new arrays to find the common numbers
        intersect = (newarray1 & newarray2)
        ## finally check which items are the two first consecutive ones
        intersect.each_index do |x|
          if intersect[x+1] == intersect[x]+1
            return [intersect[x], intersect[x+1]]
          end
        end
      end

      def get_vios_device_bible(managed_sys,vio_id)
        ## VIOS 1.5 does not have the chkdev command.
        ## the output will be nothing
        return_hash = Hash.new
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          ref_command = "viosvrcmd -m #{managed_sys} --id #{vio_id} -c \"chkdev -verbose -field name identifier pvid vtd -fmt ':'\""
          regexp_devices = /^(\w+):\w+\s(\w{5})(\w{4}).{20}:(\w{4,16}):?0{0,16}:(\w+)?/
          ref_devices = run_remote_command(ssh,ref_command).scan(regexp_devices)
          ## for vios < 2.2
          if ref_devices.length < 1
            return nil
          end
          ref_devices.each do |entry|
            return_hash[entry[0]] = { :name => entry[0],
                                      :sernum => entry[1],
                                      :ldev => entry[2],
                                      :pvid => entry[3],
                                      :vtd => entry[4]}
          end
        end
        return return_hash
      end

      def fetch_vio_maps(managed_sys,vio_id,vhost)
        array_mapping = Array.new
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          command = "viosvrcmd -m #{managed_sys} --id #{vio_id} -c \"lsmap -vadapter #{vhost} -field \\\"Backing device\\\" VTD LUN -fmt \":\"\""
          mapping = run_remote_command(ssh, command)
          if mapping.length != 5
            mapping.split(":").each_slice(3) do |item|
              if item[0] =~ /^hdisk/
                command = "viosvrcmd -m #{managed_sys} --id #{vio_id} -c \"lsdev -dev #{item[0]} -attr pvid\" | tail -n 1"
                pvid = run_remote_command(ssh, command)
                command = "viosvrcmd -m #{managed_sys} --id #{vio_id} -c \"lspv -size #{item[0]}\""
                size = run_remote_command(ssh, command).chomp
                ### Guess what device it is and if it's a Hitachi dev, fetch ArraySN & LDEV
                command = "viosvrcmd -m #{managed_sys} --id #{vio_id}  -c \"lsdev -dev #{item[0]} -vpd\""
                output = run_remote_command(ssh, command).split("\n")
                vpddata = output[2...output.length-7]
                hash = Hash.new
                vpddata.map do |x|
                  tmparr = x.split(/\.{2,}/)
                  tmparr.map!{ |y| y.gsub(/\ {2,}/,"")}
                  hash[tmparr[0]] = tmparr[1]
                end
                sernum = ""
                devid = ""
                case hash["Manufacturer"]
                when /HITACHI/
                  sernum = hash["Serial Number"][-5,+5]
                  devid = hash["Device Specific.(Z1)"][-8,+4]
                when /DGC/
                  sernum = hash["Serial Number"]
                  devid = hash["Device Specific.(UI)"]
                when /EMC/
                  sernum = hash["EC Level"]
                  devid = hash["LIC Node VPD"]
                end
              else
                pvid = ""
                sernum = ""
                devid = ""
              end
              hash = { "vtd" => item[1],
                       "lun" => item[2][0,4],
                       "backingdevice" => item[0],
                       "pvid" => pvid[0...16],
                       "sernum" => sernum,
                       "devid" => devid,
                       "size" => size }
              array_mapping.insert(-1,hash)
            end
          end
        end
        return array_mapping
      end

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
          output.gsub!("\n","")
          output.split("\n").each do |line|
            profile = parse_profile(line)
            lparinfo[:profiles].insert(-1, profile)
          end
          hash_profile[managedhost] = Array.new
          hash_profile[managedhost].insert(-1, lparinfo)
        end
        return hash_profile
      end
      def getconfig
        hash = Hash.new
        hash_mapping = Hash.new
        hash_mapping['vscsi'] = Array.new
        hash_mapping['vfc'] = Array.new
        Net::SSH.start(config[:hmc], config[:hmc_user], {:password => @hmc_passwd,:port => config[:ssh_port]}) do |ssh|
          command = "lssyscfg -r prof -m #{config[:managed_host]} --filter \"lpar_names=#{config[:partition]},profile_names=$(lssyscfg -r lpar -m #{config[:managed_host]} --filter \"lpar_names=#{config[:partition]}\" -F curr_profile)\""
          output = run_remote_command(ssh, command)
          if output =~ /The command entered has a malformed filter/
            command = "lssyscfg -r prof -m #{config[:managed_host]} --filter \"lpar_names=#{config[:partition]},profile_names=$(lssyscfg -r lpar -m #{config[:managed_host]} --filter \"lpar_names=#{config[:partition]}\" -F default_profile)\""
            output = run_remote_command(ssh, command)
          end
          if output =~ /HSCL8/
            ui.error "Error running the command"
            output.split("\n").first(2).each do |x|
              ui.error x
              exit 1
            end
            ui.error "..."
          end
          profile = parse_profile(output)
          hash[config[:managed_host]] = [profile]
          profile["virtual_scsi_adapters"].split(",").each do |vscsi|
            array_info = vscsi.split("/") ## spliting into a array the vscsi line
            clientadapterid = array_info[0].to_i
            serveradapterid = array_info[4].to_i
            vioserverid = array_info[2].to_i
            vscsiname = fetch_vio_vadapter(config[:managed_host],vioserverid,serveradapterid)
            mappings = fetch_vio_maps(config[:managed_host],vioserverid,vscsiname)
            hash_mapping['vscsi'].insert(-1, { "vios" => vioserverid, "vhost" => vscsiname, "serveradapterid" => serveradapterid, "clientadapterid" => clientadapterid, "mappings" => mappings})
          end
          if profile.has_key?("virtual_fc_adapters") and not profile["virtual_fc_adapters"] == "none"
            profile["virtual_fc_adapters"].split(",").each do |vfc|
              array_info = vfc.split("/") ## spliting into a array the vfc line
              clientadapterid = array_info[0].to_i
              serveradapterid = array_info[4].to_i
              vioserverid = array_info[2].to_i
              vfcname = fetch_vio_vadapter(config[:managed_host],vioserverid,serveradapterid)
              fcmap = fetch_vio_fcmap(config[:managed_host],vioserverid,vfcname)
              hash_mapping['vfc'].insert(-1, { "vios" => vioserverid, "vfchost" => vfcname, "serveradapterid" => serveradapterid, "clientadapterid" => clientadapterid, "wwn1" => array_info[5], "wwn2" => array_info[6], "fcmap" => fcmap })
            end
          end
          return hash_mapping
        end
      end
      def print_ok
        print "%40s\n" % ui.color('[OK]', :green)
      end
      def print_ko
        print "%40s\n" % ui.color('[KO]', :red)
      end

      def get_nim_networks
        array_return = Array.new
        Net::SSH.start(config[:nimserver], config[:nimuser], {:password => config[:nimpasswd],:port => config[:nimport]}) do |ssh|
          regexp = /(?'netname'\w+):[^:]*net_addr\s+=\s(?'netaddr'.+)\s+snm\s+=\s(?'netmask'.+)\s+routing1\s+=\s\w+\s(?'gateway'.+)[^:]/
          command = 'lsnim -l -t ent'
          output = run_remote_command(ssh,command)
          output << "\n"
          output.scan(regexp).each do |net|
            hash = { :netname => net[0],
                     :network => net[1],
                     :netmask => net[2],
                     :gateway => net[3] }
            array_return.insert(-1,hash)
          end
        end
        return array_return
      end

      def list_nim_sysref
        array_return = Array.new
        Net::SSH.start(config[:nimserver], config[:nimuser], {:password => config[:nimpasswd],:port => config[:nimport]}) do |ssh|
          command = 'lsnim -t lpp_source'
          output = run_remote_command(ssh,command)
          array_return = output.scan(/(?!\w+IOS)(^\w+_(\w+)\b)/)
        end
        return array_return.flatten
      end


      def show_wait_spinner(fps=10)
        chars = %w[| / - \\]
        delay = 1.0/fps
        iter = 0
        spinner = Thread.new do
          while iter do
              print chars[(iter+=1) % chars.length]
              sleep delay
              print "\b"
            end
          end
          yield.tap{       # After yielding to the block, save the return value
                           iter = false   # Tell the thread to exit, cleaning up after itself…
                           spinner.join   # …and wait for it to do so.
                           }                # Use the block's return value as the method's
        end
      end
    end
  end


