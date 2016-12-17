#!/bin/bash
#title           :hp_proliant_firmware_report.sh
#description     :HP Proliant Firmware Report details from LINUX.
#author		       :Amit
#date            :20160818
#version         :1.1
#usage		       :bash hp_proliant_firmware_report.sh
#notes           :Get Firmware Details for HP Prolaint Hosts.




HOST_FQDN=$(/bin/hostname)
TODAY=$(date)
RAW_DATA[0]="/var/tmp/_dmidecode_216"
RAW_DATA[1]="/var/tmp/_lspci_raid"
RAW_DATA[2]="/var/tmp/_dmidecode_bios"
RAW_DATA[3]="/var/tmp/_dmidecode_slot"




who_can_execute(){
  if [ $EUID != 0 ]; then
    echo "You need to to be Super User to execute this script"
    exit 1
  fi
}

_check_HP_hardware(){
  HW_VENDOR=$(/usr/sbin/dmidecode -q -s system-manufacturer | tail -1)
  if [ ${HW_VENDOR} != 'HP' ]; then
    echo "This should be running on HP Proliant Hardware"
    exit 1
  fi

}



_clean_me(){
  ## Clean before Gather the data remove what already exist
    for file_seq in $(seq 0 $((${#RAW_DATA[@]} -1)))
    do
      if [ -f "${RAW_DATA[${file_seq}]}" ]; then
          rm "${RAW_DATA[${file_seq}]}" 2> /dev/null
      fi
    done

}

_install_required_libs(){

  if [ ! -f /usr/bin/ipmitool ]; then
    echo "Trying to Install ipmitool"
    yum install ipmitool -y
    if [ $? -eq 0 ]; then
      echo "ipmitool is installed"
    else
      echo "Warning: ILO Firmware may or may not be current, Because ipmitool is not available."
    fi
  fi

}


# Gather Data
gather_hw_info(){
# Gather what you needed
  /usr/sbin/dmidecode -t 216 > ${RAW_DATA[0]}
  /usr/sbin/dmidecode -t bios > ${RAW_DATA[2]}

  /sbin/lspci -Dmm | grep 'RAID bus controller' | awk '{print $1","$NF}' > ${RAW_DATA[1]}
  /usr/sbin/dmidecode -t slot | egrep "Designation: PCI-E Slot|Bus Address:" > ${RAW_DATA[3]}

}


## Reporting Begin's Here --

_report_ilo_firmware() {
  # To get ILO Firmware
  if [ ! -f /usr/bin/ipmitool ]; then
    modprobe ipmi_devintf
    modprobe ipmi_si
    FIRMWARE_ILO=$(/usr/bin/ipmitool mc info | grep -w "Firmware Revision" | awk '{print $NF}')
    printf "| %-50s | %-30s | %-20s |\n" "ILOv4 Firmware" "${FIRMWARE_ILO}" "Embedded"
  else
    FIRMWARE_ILO=$(grep -w "[[:space:]]Firmware Revision:" ${RAW_DATA[2]} | sed -e 's/^[ \t]*//' | awk '{print $NF}')
    printf "| %-50s | %-30s | %-20s |\n" "ILOv4 Firmware" "${FIRMWARE_ILO}" "Embedded"
  fi

}

_report_hw_details(){

  HardwareVendor=$(/usr/sbin/dmidecode -q -s system-manufacturer |tail -1)
  HardwareProduct=$(/usr/sbin/dmidecode -q -s system-product-name | tail -1)
  HardwareSerial=$(/usr/sbin/dmidecode -q -s system-serial-number | tail -1)

  printf "%-20s : %-20s\n" "Hardware Vendor" "${HardwareVendor}"
  printf "%-20s : %-20s\n" "Hardware Product" "${HardwareProduct}"
  printf "%-20s : %-20s\n" "Hardware Serial" "${HardwareSerial}"


}


_report_bios_firmware() {
  # To get Bios Firmware

  BIOS_VERSION=$(/usr/sbin/dmidecode -q -s bios-version | tail -1)
  BIOS_RELEASE_DATE=$(/usr/sbin/dmidecode -q -s bios-release-date | tail -1)
  BIOS_FW_REVISION=$(grep -w "[[:space:]]BIOS Revision:" ${RAW_DATA[2]} | sed -e 's/^[ \t]*//' | awk '{print $NF}')

  BIOS_DATA="${BIOS_VERSION} ${BIOS_FW_REVISION} ${BIOS_RELEASE_DATE}"
  printf "| %-50s | %-30s | %-20s |\n" "Bios Info" "${BIOS_DATA}" "Embedded"

}


_report_raid_firmware() {
  # Gather RAID details and firmware information

  RAID_PCI=()
  RAID_MODEL=()
  RAID_LOCATION=()
  RAID_FIRMWARE=()

  RAID_CARD_COUNT=$(wc -l ${RAW_DATA[1]}|awk '{print $1}')

  if [ ${RAID_CARD_COUNT} != "0" ]; then

    for raid_number in $(seq 0 $((${RAID_CARD_COUNT} -1)))
    do
      READJUST_SEQ=$((${raid_number} +1))
      RAID_PCI[${raid_number}]=$(head -n ${READJUST_SEQ} ${RAW_DATA[1]} | tail -1 | awk -F, '{ print $1 }')
      RAID_MODEL[${raid_number}]=$(head -n ${READJUST_SEQ} ${RAW_DATA[1]} | tail -1 | awk -F, '{ print $NF }'| sed 's/\"//g')

      grep -B 1 -w "${RAID_PCI[${raid_number}]}" ${RAW_DATA[3]} > /dev/null 2>&1

      if [ $? -eq 0 ]; then
        RAID_LOCATION[${raid_number}]=$(grep -B 1 -w "${RAID_PCI[${raid_number}]}" ${RAW_DATA[3]} | grep 'Designation:' | awk -F: '{print $NF}' | sed 's/^[[:blank:]]*//')
      else
        RAID_LOCATION[${raid_number}]="Embedded"
      fi

      ls -1 /sys/devices/pci0000:00/*//${RAID_PCI[${raid_number}]}/host?/scsi_host/host?/firmware_revision > /dev/null 2>&1

      if [ $? -eq 0 ]; then
        array_fw_find=$(ls -1 /sys/devices/pci0000:00/*//${RAID_PCI[${raid_number}]}/host?/scsi_host/host?/firmware_revision)
        RAID_FIRMWARE[${raid_number}]=$(cat ${array_fw_find})
      else
        RAID_FIRMWARE[${raid_number}]="Not Found"
      fi

    done

    for firmware_element in $(seq 0 $((${RAID_CARD_COUNT} -1)))
    do
      printf "| %-50s | %-30s | %-20s |\n" "Smart Array Model - ${RAID_MODEL[${firmware_element}]} Controller" "${RAID_FIRMWARE[${firmware_element}]}" "${RAID_LOCATION[${firmware_element}]}"
    done

  else
    printf "| %-50s | %-30s | %-20s |\n" "Smart Array Controller" "NA" "Not Found"
  fi


}


_report_other_firmware() {


FIRMWARE_VER=()
FIRMWARE_NAME=()

FIRMWARE_NAME[0]="System ROM"
FIRMWARE_NAME[1]="Redundant System ROM"
FIRMWARE_NAME[2]="System ROM Bootblock"
FIRMWARE_NAME[3]="Power Management Controller Firmware"
FIRMWARE_NAME[4]="Power Management Controller Firmware Bootloader"
FIRMWARE_NAME[5]="HPE Smart Storage Battery 1 Firmware"
FIRMWARE_NAME[6]="Intelligent Platform Abstraction Data"




  for firmware_element in $(seq 0 $((${#FIRMWARE_NAME[@]} - 1)))
  do
    FIRMWARE_VER[${firmware_element}]=$(grep -A 1 -w "[[:space:]]${FIRMWARE_NAME[${firmware_element}]}$" ${RAW_DATA[0]} | tail -1 | sed -e 's/^[ \t]*//')

    if [[ -z ${FIRMWARE_VER[${firmware_element}]} ]]; then
      FIRMWARE_VER[${firmware_element}]="Not Found"
    fi

  done

  for firmware_element in $(seq 0 $((${#FIRMWARE_NAME[@]} - 1)))
  do
    printf "| %-50s | %-30s | %-20s |\n" "${FIRMWARE_NAME[${firmware_element}]}" "${FIRMWARE_VER[${firmware_element}]}" "Embedded"
  done




}







#########################################
####    MAIN EXEUCTION BEGINS FROM HERE
####
#########################################


who_can_execute
_check_HP_hardware
gather_hw_info
/usr/bin/clear
echo
_install_required_libs
echo
_report_hw_details
echo
printf '%110s\n' | tr ' ' -
printf "| %-50s | %-30s | %-20s |\n" "Component Name" "Version" "Location"
printf '%110s\n' | tr ' ' -
_report_ilo_firmware
_report_bios_firmware
_report_other_firmware
_report_raid_firmware
printf '%110s\n' | tr ' ' -
