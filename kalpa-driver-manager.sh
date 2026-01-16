#!/usr/bin/bash

TITLE="Kalpa Driver Manager"
NVIDIA_VENDOR_ID="0x10de"
NVIDIA_GPU_CLASSES=("0x030000" "0x030200") # "desktop_gpu" "mobile_gpu"
PCI_DEVICE_PATH="/sys/bus/pci/devices/"

supported_driver_series="none"
found_nvidia_device="none"
found_nvidia_gpu_but_device_id_does_not_match_support_matrix=false
user_agreed_to_license=false

#G0: Unsupproted
#G6-closed: G06 driver with closed module
#G06-open: G06 driver with open module
#G07: G07 driver there is ust the open module
declare -A GPU_SUPPORT_MATRIX=(
    ["G0"]="0x1290;0x1291;0x1294;0x1298;0x11e0;0x11a0;0x1199;0x119e;0x11a9;0x0fd9;0x0fe1;0x0fd2;0x0fd5;0x0fec;0x0fe4;0x1198"
    ["G06-closed"]=""
    ["G06-open"]=""
    ["G07"]=""
)

enroll_mok(){
    echo "MOK enrolement not implemented yet"
}

# Scanns all PCI devices for vendor nvidia
# If nvidia devices found checks if it is of type GPU
# If it is a nvidia GPU check if it is supported accrording to the support matrix
detect_nvidia_gpu_and_supported_driver(){
    for device in $PCI_DEVICE_PATH*; do
        vendor_id=$(cat ${device}/vendor)
        if [ $vendor_id == $NVIDIA_VENDOR_ID ]; then
            device_class=$(cat ${device}/class)
            for nvidia_gpu_class in ${NVIDIA_GPU_CLASSES[@]}; do
                if [ $device_class == $nvidia_gpu_class ]; then
                    found_nvidia_device=$(cat ${device}/device)
                    for driver_series in ${!GPU_SUPPORT_MATRIX[@]}; do
                        IFS=";" read -r -a supported_gpus_by_driver <<< "${GPU_SUPPORT_MATRIX[$driver_series]}"
                        for gpu_id in ${supported_gpus_by_driver[@]}; do
                            if [ $gpu_id == $found_nvidia_device ]; then
                                supported_driver_series=$driver_series
                                echo "Found supported driver series: $supported_driver_series for device $found_nvidia_device"
                            fi
                        done
                    done
                fi
            done
        fi
    done
}

detect_kdialog(){
    if command -v kdialog >/dev/null 2>&1; then
        has_kdialog=true
    else
        if command -v zenity >/dev/null 2>&1; then
            zenity --error --title "$TITLE" --text "KDialog not found. This tool is to be used on Kalpa Desktop. You probably are running Aeon Desktop which is not supported by this utility"
        else
            echo "No supported dialog software found. Exiting"
        fi
        exit 1
    fi

}

analyze_system(){
    # Is Kalpa Dekstop and / or MicroOS: No - Inform user, then Quit
    # Has nVidia GPU: No - Infomr user, then Quit
    # Has supported nVidia GPU: No - Inform user, then Quit
    # Is nvidia GPU supported by open kernel module: No - Check SecureBoot
    #   Has SecureBoot enabled: Yes - Add this script with --mok to autostart to enroll MOK on next system start, inform user
    #   Has SecureBoot enabled: No - Skip MOK enrollment
    detect_kdialog
    detect_nvidia_gpu_and_supported_driver
}

user_consent(){
    kdialog --title "$TITLE" --msgbox "This tool will setup and install the propriatary nVidia driver. This driver is not developed by Kalpa and using it is on your own risk.\n\nBy continuing you agree to the NVIDIA Driver License Agreement to be found here: https://www.nvidia.com/en-us/drivers/nvidia-license/linux/"

    if kdialog --title "$TITLE" --yesno "Do you accept the NVIDIA Driver License Agreement?"; then
        user_agreed_to_license=true
    fi
}

do_install(){
    echo "Performing install..."
}

read_commandline(){
    for i in "$@"; do
        case $i in
            -m*|--mok*)
            analyze_system
            enroll_mok
            ;;
            *)
                    # Unknonw option
            ;;
        esac
    done
}

main(){
    analyze_system

    if [ $found_nvidia_device == "none" ]; then
        kdialog --title "$TITLE" --sorry "Kalpa was unable to detect any NVIDIA graphics device in this computer."
    else
        user_consent
        if [ $user_agreed_to_license = true ]; then
            case $supported_driver_series in
                "G0")
                    kdialog --title "$TITLE" --sorry "Kalpa detected an NVIDIA GPU (Device ID: $found_nvidia_device) but it is not considered to deliver a good experience. If you believe this to be a mistake please check your graphics card at: https://www.nvidia.com/en-us/drivers/. If the minimum suported driver series is 500 or newer please report this issue to Kalpa Desktop."
                ;;
                "none")
                    if kdialog --title "$TITLE" --yesno "Kalpa detected a NVIDIA GPU (Device ID: $found_nvidia_device) but couldn't match it with any supported driver series. We will try to install the latest driver. Do you want to continue?"; then
                        do_install
                    fi
                ;;
                *)
                    do_install
                ;;
            esac
        fi
    fi
}

if [ "$#" -eq 0 ]; then
    main
else
    read_commandline $@
fi