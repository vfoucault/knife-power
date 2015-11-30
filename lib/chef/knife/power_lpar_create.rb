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
require 'rubygems'
require 'json-schema'
require 'pp'
require 'json'

# JSON Input file exemple
# { "managedsys": "p770-1
#   "lparname": "lpar1",
#   "vp": 2,
#   "mem": 8,
#   "ldevs": [ "17E87:02E4"],
#   "vdevs":
#       {
#         "vscsi":
#           {
#             "vio1": [20,22],
#             "vio2": [21,23]
#           },
#         "vfc":
#           {
#             "vio1": [30,"fcs0"],
#             "vio2": [31,"fcs3"]
#            },
#         "vnet": [2309]
#         }
# }


class Chef
  class Knife
    class PowerLparCreate < Knife
      include Chef::Knife::PowerCommon
      include Chef::Knife::PowerCreateSchema
      ###
      ### Set of tools to lpar configuration
      ### => used to get hdisk : vio : adapter : vscsi mappings
      ###
      banner "knife power lpar create [options]"

      option :configfile,
        :short => "-C configfile",
        :long => "--config-file configfile",
        :description => "optional configuration to use",
        :default => "~/knife-power-config.yml"

      option :json_config_file,
        :short => "-e jsonfile",
        :long => "--json-config jsonfile",
        :description => "Source Json configuration file"

      option :debug,
	:long => "--debug",
	:description => "Enable debugging mode",
	:default => false
      

      ## let's roll
      def run
	debug = config[:debug] || false
        initsettings()
        check_params
        @profile = Hash.new
        @input_data = validate_config_file
        #### creating objects :
        @myhmc = PowerVMTools::HMC.new(config[:hmc],{ :user => config[:hmc_user], :passwd => config[:hmcpasswd], :port => config[:ssh_port],:debug => debug })
	@profile[:vios] = Array.new
	@profile[:vadapters] = Hash.new
        check_frame_lpar
        @myframe.vioservers.each do |vios|
          @profile[:vios].insert(-1,[vios.id,vios.name])
        end
        check_networks
        res = check_disk_presence
        ## ended with check, let setup the lpar now
        prep_memory_cpu
        getvscsiids
        create_partition
        ##
	get_devices_name
        create_vscsi_mappings
        create_vfc_mappings
        ui.info "\nPartition #{ui.color(@input_data["lparname"], :cyan)} created on host #{ui.color(@input_data["managedsys"], :cyan)}"
        if @input_data["vdevs"]["vfc"]
	  #let's fetch the vfc adapters wwn's
	  vfcinfos = @mylpar.getvfcmappings
          ui.info "client fcs0 wwn1 : #{ui.color(vfcinfos[0][:wwn1], :cyan)} wwn2 : #{ui.color(vfcinfos[0][:wwn2], :cyan)}"
          ui.info "client fcs1 wwn1 : #{ui.color(vfcinfos[1][:wwn1], :cyan)} wwn2 : #{ui.color(vfcinfos[1][:wwn2], :cyan)}"
        end
        #run_lpar_netboot
      end

      def check_params
        if config[:hmc].nil?
          ui.error "No HMC parameter specified"
          show_usage
          exit 1
        end
        if not config[:json_config_file]
          ui.error "No Configuration file specified. Aborting!"
          exit 1
        elsif not File.exists?(config[:json_config_file])
          ui.error "Configuration file not found."
          exit 1
        end
      end

      def get_devices_name
	## will get the devices name
	viossymb = [:vios1,:vios2]
	currentid = nil
	currentvio = nil
	# {1=>[[50, "vhost0"], [51, "vhost1"]], 2=>[[50, "vhost0"], [51, "vhost1"]]}
	@mylpar.getvioadaptersnames.each_pair do |vioid,devices|
	    currentvio = viossymb.shift
	    @profile[:vadapters][currentvio] = Array.new if not @profile[:vadapters].has_key?(currentvio)
	    @profile[:vadapters][currentvio] = devices
	   end 
      end

      def create_vscsi_mappings
        if @input_data["ldevs"]
          vio1vhost = @profile[:vadapters][:vios1][0][1]
          vio2vhost = @profile[:vadapters][:vios2][0][1]
          counter = 0
          @profile[:hdisks][:vio1].each do |disk|
	    devname = disk[:name]
	    sernum = disk[:sernum]
	    ldev = disk[:ldev]
            friendlyname = @friendlynames[:storagearray][sernum]
            if counter == 0
              drivetype = "r"
            elsif counter == 1
              drivetype = "s"
            else
              drivetype = "d"
            end
            vtdname = @input_data["lparname"][0,7]+drivetype+friendlyname[-3,3]+ldev
            counter += 1
            @myframe.vioservers[0].createmapping(devname,vio1vhost,{:vtdname => vtdname, :force => true})
          end
          counter = 0
          @profile[:hdisks][:vio2].each do |disk|
	    devname = disk[:name]
	    sernum = disk[:sernum]
	    ldev = disk[:ldev]
            friendlyname = @friendlynames[:storagearray][sernum]
            if counter == 0
              drivetype = "r"
            elsif counter == 1
              drivetype = "s"
            else
              drivetype = "d"
            end
            vtdname = @input_data["lparname"][0,7]+drivetype+friendlyname[-3,3]+ldev
            counter += 1
            @myframe.vioservers[1].createmapping(devname,vio2vhost,{:vtdname => vtdname, :force => true})
          end
        end
      end

      def create_vfc_mappings
        if @input_data["vdevs"]["vfc"]
          vio1vfcname = @profile[:vadapters][:vios1].map{ |x| x.grep(/vfchost/).join}.delete_if { |x| x == ""}[0]
          vio2vfcname = @profile[:vadapters][:vios2].map{ |x| x.grep(/vfchost/).join}.delete_if { |x| x == ""}[0]
          vio1fcname = @input_data["vdevs"]["vfc"]["vio1"][1]
          vio2fcname = @input_data["vdevs"]["vfc"]["vio2"][1]
          @myframe.vioservers[0].mkfcmap(vio1vfcname,vio1fcname)
          @myframe.vioservers[1].mkfcmap(vio2vfcname,vio2fcname)
        end
      end

      def create_partition
        ### Prep virtual_eth_adapters
        vethid = 2
        @input_data["vdevs"]["vnet"].each do |vlan|
          @profile[:virtual_eth_adapters] = "#{vethid}/0/#{vlan}//0/0/ETHERNET0"
          vethid += 1
        end
        @mylpar = PowerVMTools::Lpar.new(@input_data["lparname"],{:frame => @myframe, :debug => config[:debug] })
        options = { :mem => @profile[:mem],
                    :cpu => @profile[:cpu],
                    :ame => @input_data["ame"],
                    :procmode => "shared",
                    :sharing_mode => "uncap",
                    :uncap_weight => "128",
                    :max_virtual_slots => "64",
                    :profile_name => "default",
                    :virtual_eth_adapters => @profile[:virtual_eth_adapters],
                    :virtual_scsi_adapters => @profile[:virtual_scsi_adapters].join(","),
                    :virtual_fc_adapters => @profile[:virtual_fc_adapters].join(",")}
        @mylpar.setsettings(options)
        @mylpar.create({:test => false })
      end

      def getvscsiids
        ### will fetch our vscsid
        array_res = Array.new(2, (0..9).to_a)
        # inserting values lower than 10 to prevent any missuage
	@myframe.vioservers[0].vadapters.each do |vadapter|
	  array_res[0].push(vadapter[:said].to_i)
	end
	@myframe.vioservers[1].vadapters.each do |vadapter|
	  array_res[1].push(vadapter[:said].to_i)
	end
        #array_res.map{|x| x.insert(1,2,3,4,5,6,7,8,9).uniq!}
	array_res.map { |x| x.sort!.uniq! }
        if @input_data["vdevs"]["vscsi"]
          vscsids = commonids(array_res[0],array_res[1])
          @profile[:virtual_scsi_adapters] = Array.new
          #clientsid = (20...24).to_a
          clientsid = (@input_data["vdevs"]["vscsi"]["vio1"][0]...@input_data["vdevs"]["vscsi"]["vio2"][1]+1).to_a
          clientsid.product(vscsids,@profile[:vios]).each_slice(5) do |slice|
            ## tricky again here. we must map each adapter id (clientid), on the correct vio/adapter id couple
            # making a product of clientsid & scsiids/viosid, we get array with a length of 16 (4 clientsid * 2 vscsids * 2 @profile[:vios])
            # we must shift every result by one to increment the correct result,
            ## First result ok => 0, then 4+1, then 4+1, then 4+1 again. Each 5 item we have the correct mix
            # [[20, 9, ["1", "viosrv1"]],
            #  [21, 9, ["2", "viosrv2"]],
            #  [22, 10, ["1", "viosrv1"]],
            #  [23, 10, ["2", "viosrv2"]]]
            cltadapid = slice[0][0]
            srvadapid = slice[0][1]
            viosrvid = slice[0][2][0]
            viosrvname = slice[0][2][1]
            @profile[:virtual_scsi_adapters].insert(-1,"#{cltadapid}/client/#{viosrvid}/#{viosrvname}/#{srvadapid}/0")
            ## We must add the chosen adapters id to the array containing the used adapters id to find the good ones
            ## in case of vfc adapters (lower)
            array_res.map{|x| x.insert(1,srvadapid).sort!.uniq!}
          end
          @profile[:vscsids] = vscsids
        end
        if @input_data["vdevs"]["vfc"]
          ### we must setup the two vfc adapters for the partition
          vfcids = commonids(array_res[0],array_res[1])
          @profile[:virtual_fc_adapters] = Array.new
          clientsid = [@input_data["vdevs"]["vfc"]["vio1"][0],@input_data["vdevs"]["vfc"]["vio2"][0]]
          counter = 0
          clientsid.each do |vfc|
            @profile[:virtual_fc_adapters].insert(-1,"#{vfc}/client/#{@profile[:vios][counter][0]}/#{@profile[:vios][counter][1]}/#{vfcids[0]}//0")
            counter += 1
          end
          @profile[:vfcids] = vfcids[0]
        end
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

      def prep_memory_cpu
        amefactor = @input_data["ame"]
        targetmem = @input_data["mem"] * 1024
        # the default memory region on a Power System
        memoryregion = 256
        ### check it anyway
	command = "lshwres -m #{@myframe.name} --level sys -r mem -F mem_region_size"
        memoryregion = @myhmc.run_command(command).chomp.to_i
        power10 =  (3..9).collect { |x| 2**x*1024 }.to_a.insert(0,0)
        power10.each_index do |x|
          if targetmem <= power10[x]
            ## very simple : for 2
            #  (2 * 1024 / 1.2 ).ceil => 1707
            #  (1708 / 256).ceil = 7
            #  (7 * 256) = 1792
            #  at the end, if the memory rounded to the memoryregion is lower than
            #  the expected memory, we add another time the memory region
            arrangedmemory = ((targetmem / amefactor).ceil.to_f / memoryregion).ceil * memoryregion
            arrangedmemory + memoryregion if (arrangedmemory * amefactor) < targetmem
            @profile[:mem] = { :max => power10[x+1],
                               :min => 1024,
                               :des => arrangedmemory }
            break
          end
        end
        @profile[:cpu] = { :desec => @input_data["vp"].to_f / 10,
                           :minec => 0.1,
                           :maxec => @input_data["vp"].to_f / 5,
                           :desvp => @input_data["vp"],
                           :minvp => 1,
                           :maxvp => @input_data["vp"] * 2 }
      end

      def check_disk_presence
        if @input_data["ldevs"]
          array1 = Array.new
          array2 = Array.new
          vios1disks = @myframe.vioservers[0].get_hdisk_bible
          vios2disks = @myframe.vioservers[1].get_hdisk_bible
          vios1disks.each { |v| array1.push(v[:sernum] + ":" + v[:ldev])}
          vios2disks.each { |v| array2.push(v[:sernum] + ":" + v[:ldev])}
          return "Both Vios don't share the exact same disks" if not array1.sort == array2.sort
          ### let's work on array1
          # let's find the hdisks name on each VIOs
          missingdisks = Array.new
          @profile[:hdisks] = Hash.new
          @profile[:hdisks][:vio1] = Array.new
          @profile[:hdisks][:vio2] = Array.new
          @input_data["ldevs"].each do |disk|
            missingdisk.push(disk) if not array1.include?(disk)
            sernum,ldev = disk.split(":")
            @profile[:hdisks][:vio1].push(vios1disks.select { |v| v[:sernum] == sernum and v[:ldev] == ldev and v[:vtd] == nil}.flatten[0])
            @profile[:hdisks][:vio2].push(vios2disks.select { |v| v[:sernum] == sernum and v[:ldev] == ldev and v[:vtd] == nil}.flatten[0])
          end
          ## check to be sure that none of the ldevs are already used as backing devices on those VIOs (removed entries from above)
          @profile[:hdisks][:vio1].select! { |x| x.length > 0 if not x.nil?}
          @profile[:hdisks][:vio2].select! { |x| x.length > 0 if not x.nil?}
          if @input_data["ldevs"].length == @profile[:hdisks][:vio1].length and @profile[:hdisks][:vio1].length ==  @profile[:hdisks][:vio2].length
            return "ok"
          else
            ui.error "Error with some disks. Check ldevs"
	    ui.error "Requested Devices : #{@input_data["ldevs"]}"
	    ui.error "Disks Available on VIO1 : #{@profile[:hdisks][:vio1]}"
	    ui.error "Disks Available on VIO2 : #{@profile[:hdisks][:vio2]}"
	    exit 1
          end
        else
          return "No LDEVs to process"
        end
      end

      def check_networks
        networks = @myframe.networks
        unavailable_nets = Array.new
        ### is the vlan yet defined on each VIOs
        viosnet = Array.new
        @myframe.vioservers.map { |x| viosnet.push(x.networks) }
        viosnet.flatten!.sort!.uniq!
        @input_data["vdevs"]["vnet"].each do |vnet|
          res = networks.select { |x| x[:vlan_id] == vnet }
          unavailable_nets.push(vnet) if not res.length > 0
          res = viosnet.select { |x| x == vnet }
          unavailable_nets.push(vnet) if not res.length > 0
        end
        unavailable_nets.sort.uniq
        if unavailable_nets.length > 0
          ui.error "Some networks aren't available on Frame #{self.name} or VIOs"
          ui.error "VLANS => #{ unavailable_nets.map { |x| printf x }} "
          exit 1
        end
        #### done for net check
      end

      def check_frame_lpar
        ## check if frame exists
        if not @myhmc.framesbystatus("Operating").include?(@input_data["managedsys"])
         ui.error "Frame #{@input_data["managedsys"]} does not exists or is not in a proper state"
         exit 1
        end
        @myframe = PowerVMTools::Frame.new(@input_data["managedsys"],@myhmc)
        if @myframe.lpars.include?(@input_data["lparname"])
          ui.error "Lpar #{@input_data["lparname"]} Already exists on this Frame"
	  exit 1
        end
      end
    end
  end
end
