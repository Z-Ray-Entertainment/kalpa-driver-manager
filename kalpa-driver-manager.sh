#!/usr/bin/bash

TITLE="Kalpa Driver Manager"
NVIDIA_VENDOR_ID="0x10de"
NVIDIA_GPU_CLASSES=("0x030000" "0x030200") # "desktop_gpu" "mobile_gpu"
PCI_DEVICE_PATH="/sys/bus/pci/devices/"
TU_CONFIG_FILE="/etc/transactional-update.conf.d/40-import-key.conf"
LOG_FILE=${HOME}/kalpa-driver-manager.log
AUTOSTART_FILE="$HOME/.config/autostart/kalpa-driver-manager-mok.desktop"
AUTOSTART_VALIDATE_FILE="$HOME/.config/autostart/kalpa-driver-manager-validate.desktop"

NV_DRIVER_G00="G00"
NV_DRIVER_G04="G04"
NV_DRIVER_G05="G05"
NV_DRIVER_G06_CLOSED="G06-closed"
NV_DRIVER_G06_OPEN="G06-open"
NV_DRIVER_G07="G07"

NVIDIA_DRIVER_MODULES=("nvidia_drm" "nvidia_modeset" "nvidia_uvm")

supported_driver_series="none"
found_nvidia_device="none"
user_agreed_to_license=false

required_binaries=("kdesu" "kdialog" "qdbus6" "/usr/sbin/transactional-update" "sed")
missing_binaries=()

is_system_ready_for_rocm=false
is_system_ready_for_nvidia=false

is_on_battery=false
is_power_saving=false
is_secure_boot_enabled=false
is_distro_supported=false

declare -A GPU_SUPPORT_MATRIX=(
    # Curie, Tesla 2.0 there are no drivers available
    ["$NV_DRIVER_G00"]="0x10c3;0x10c5;0x10d8;0x0ca8;0x0ca9;0x0cac;0x0caf;0x0cb0;0x0cb1;0x0cbc;0x0ca0;0x0ca2;0x0ca3;0x0ca4;0x0ca5;0x0ca7;0x0be2;0x0a75;0x0a76;0x0a78;0x0a7a;0x0a7b;0x0a7c;0x0a6e;0x0a6f;0x0a70;0x0a71;0x0a72;0x0a73;0x0a74;0x0a65;0x0a66;0x0a67;0x0a68;0x0a69;0x0a6a;0x0a6c;0x0a34;0x0a35;0x0a38;0x0a3c;0x0a60;0x0a62;0x0a63;0x0a64;0x0a28;0x0a29;0x0a2a;0x0a2b;0x0a2c;0x0a2d;0x0a30;0x0a32;0x0a20;0x0a21;0x0a22;0x0a23;0x0a26;0x0a27;0x0a24;0x087a;0x087d;0x087e;0x087f;0x086e;0x0870;0x0871;0x0872;0x0873;0x0874;0x0876;0x0866;0x0867;0x0868;0x086a;0x086c;0x086d;0x084d;0x084f;0x0860;0x0861;0x0862;0x86;0x0863;0x0864;0x0865;0x0845;0x0846;0x0847;0x0848;0x0849;0x084a;0x084b;0x084c;0x07e5;0x0840;0x0844;0x07e0;0x07e1;0x07e2;0x07e3"
    # Fermi, while there is a driver it is not going to work with Wayland and therefore not with Kalpa
    ["$NV_DRIVER_G04"]="0x1140;0x124b;0x124d;0x1251;0x1245;0x1246;0x1247;0x1248;0x1249;0x1212;0x1213;0x1241;0x1243;0x1244;0x1206;0x1207;0x1208;0x1210;0x1211;0x1200;0x1201;0x1202;0x1203;0x1205;0x108b;0x108e;0x1091;0x1094;0x1096;0x109a;0x109b;0x10c0;0x1082;0x1084;0x1086;0x1087;0x1088;0x1089;0x105a;0x105b;0x107c;0x107d;0x1080;0x1081;0x1052;0x1054;0x1055;0x1056;0x1057;0x1058;0x1059;0x1049;0x104a;0x104b;0x104c;0x104d;0x1050;0x1051;0x1040;0x1042;0x1045;0x1048;0x0f00;0x0f01;0x0f02;0x0f03;0x0f06;0x0e22;0x0e23;0x0e24;0x0e30;0x0e31;0x0e3a;0x0e3b;0x0e0c;0x0df8;0x0df9;0x0dfa;0x0dfc;0x0df2;0x0df3;0x0df4;0x0df5;0x0df6;0x0df7;0x0dea;0x0deb;0x0dec;0x0ded;0x0dee;0x0def;0x0df0;0x0df1;0x0de2;0x0de3;0x0de4;0x0de5;0x0de7;0x0de8;0x0de9;0x0dd2;0x0dd3;0x0dd6;0x0dd8;0x0dda;0x0de0;0x0de1;0x0dc0;0x0dc4;0x0dc5;0x0dc6;0x0dcd;0x0dce;0x0dd1"
    # Kepler, while there is a driver which has limited Wayland support and in theory works with Kalpa they tend to break on major Kernel releases
    ["$NV_DRIVER_G05"]="0x12b9;0x12ba;0x11be;0x11fc;0x11b6;0x11b7;0x11b8;0x11bc;0x11bd;0x11af;0x11a8;0x0ff8;0x0ffb;0x0ffc;0x0ff6;0x11b9;0x1290;0x1299;0x129a;0x1291;0x1292;0x1293;0x1294;0x1295;0x1296;0x1298;0x11e2;0x11e3;0x11e0;0x11e1;0x119f;0x11a0;0x11a1;0x11a2;0x1199;0x119a;0x119d;0x119e;0x11a3;0x11a7;0x11a9;0x0fe8;0x0fe9;0x0fd9;0x0fdf;0x0fe0;0x0fe1;0x0fe2;0x0fd1;0x0fd2;0x0fd3;0x0fd4;0x0fd5;0x0fd8;0x0fea;0x0fec;0x0fed;0x0fee;0x0fe3;0x0fe4;0x0fcd;0x0fce;0x1198;0x0fdb;0x0fd6;0x11e7;0x11fa;0x11bf;0x11ba;0x11bb;0x11b0;0x11b1;0x11b4;0x118f;0x1194;0x103a;0x103c;0x1022;0x118a;0x118b;0x118d;0x101e;0x101f;0x1020;0x1021;0x0fff;0x102d;0x1024;0x1026;0x1028;0x0ff9;0x0ffa;0x0ffe;0x0ff2;0x0ff3;0x0ff5;0x0ff7;0x0fef;0x0fe7;0x102e;0x102f;0x1023;0x1029;0x102a;0x1027;0x103f;0x1003;0x1004;0x1005;0x1007;0x1008;0x1286;0x1289;0x1280;0x1281;0x1282;0x1284;0x11c7;0x11c8;0x11cb;0x11c3;0x11c4;0x11c5;0x11c6;0x11c0;0x11c2;0x1191;0x1193;0x118e;0x1186;0x1184;0x1185;0x1187;0x1195;0x1188;0x1189;0x118c;0x1180;0x1182;0x1183;0x0ffd;0x0ff1;0x0fe5;0x0fe6;0x0fc5;0x0fc6;0x0fc8;0x0fc9;0x0fc0;0x0fc1;0x0fc2;0x1287;0x1288;0x128b;0x100c;0x1001;0x100a;0x128a;0x128c;0x12a0"
    # Maxwell, Pascal, Volta using closed source Kernel module as these GPUs lack the GSP co-processor
    ["$NV_DRIVER_G06_CLOSED"]="0x1436;0x13fb;0x13f8;0x13f9;0x13fa;0x13b1;0x13b2;0x13b3;0x13b4;0x13b6;0x13b0;0x137a;0x137b;0x1667;0x174d;0x174e;0x1617;0x1618;0x1619;0x161a;0x1427;0x13d7;0x13d8;0x13d9;0x13da;0x1398;0x1399;0x139a;0x139b;0x139c;0x139d;0x1390;0x1391;0x1392;0x1393;0x134d;0x134e;0x134f;0x137d;0x1344;0x1346;0x1347;0x1348;0x1349;0x134b;0x1340;0x1341;0x17f0;0x17f1;0x17fd;0x1789;0x1430;0x1431;0x13f1;0x13f2;0x13f3;0x13e7;0x13f0;0x13ba;0x13bb;0x13bc;0x13bd;0x13b9;0x1389;0x17c2;0x17c8;0x179c;0x1401;0x1402;0x1406;0x1407;0x1404;0x13c0;0x13c2;0x1381;0x1382;0x1380;0x13c1;0x13c3;0x1d34;0x1d33;0x1cbc;0x1cbd;0x1cba;0x1cbb;0x1bb5;0x1bb6;0x1bb7;0x1bb8;0x1bb9;0x1bbb;0x1d10;0x1d11;0x1d12;0x1d13;0x1d16;0x1c92;0x1c94;0x1c96;0x1c8c;0x1c8d;0x1c8f;0x1c90;0x1c91;0x1c21;0x1c22;0x1c23;0x1c35;0x1c20;0x1ba0;0x1ba1;0x1ba2;0x1be0;0x1be1;0x1d52;0x1d56;0x1ccc;0x1ccd;0x1c60;0x1c61;0x1c62;0x1c8e;0x1c2d;0x1baa;0x1ba9;0x1cfa;0x1cfb;0x1cb6;0x1cb1;0x1cb2;0x1cb3;0x1c30;0x1c31;0x1bb0;0x1bb1;0x1bb3;0x1bb4;0x1b39;0x15f9;0x15f0;0x15f7;0x15f8;0x1b30;0x1b38;0x15f1;0x1c70;0x1ca7;0x1ca8;0x1caa;0x1b70;0x1b78;0x1d01;0x1d02;0x1c83;0x1c81;0x1c82;0x1c36;0x1c03;0x1c04;0x1c06;0x1c07;0x1c09;0x1bc7;0x1bad;0x1b83;0x1b84;0x1b87;0x1c02;0x1b80;0x1b81;0x1b82;0x1b02;0x1b06;0x1b07;0x1af1;0x1b00;0x1b01;0x1b04;0x1725;0x172e;0x172f;0x1c00;0x1c01;0x1df0;0x1df2;0x1df5;0x1df6;0x1db4;0x1db5;0x1db6;0x1db7;0x1db8;0x1dba;0x1db1;0x1db2;0x1db3;0x1dbe;0x1d81"
    # Turing, Hopper, Ampere, Ada, Blackwell using open source Kernel module
    ["$NV_DRIVER_G06_OPEN"]="0x1ff9;0x1fb8;0x1fb9;0x1fb6;0x1fb7;0x1fbc;0x1fbb;0x1fba;0x1fb0;0x1fb2;0x1f76;0x1f36;0x1ef5;0x1eb5;0x1eb6;0x21d1;0x1fd9;0x1fdd;0x1f55;0x1f50;0x1f51;0x1f54;0x1ed3;0x1ed0;0x1ed1;0x2191;0x2192;0x1f9f;0x1fa0;0x1f98;0x1f9c;0x1f9d;0x1f92;0x1f94;0x1f95;0x1f96;0x1f97;0x1f10;0x1f11;0x1f12;0x1f14;0x1f15;0x1f91;0x1eae;0x1e90;0x1e91;0x1e93;0x1f99;0x1fa1;0x1f2e;0x1eab;0x1ff0;0x1ff2;0x1fb1;0x1eb8;0x1eba;0x1eb4;0x1eb0;0x1eb1;0x1e37;0x1e38;0x1e78;0x1e30;0x1e36;0x21ae;0x21bf;0x1fbf;0x1fae;0x1eb9;0x1ebe;0x1e3c;0x1e3d;0x1e3e;0x21c4;0x2188;0x2189;0x2182;0x2184;0x2187;0x1f82;0x1f83;0x1f42;0x1f47;0x1f0b;0x1f06;0x1f07;0x1f08;0x1f09;0x1f0a;0x1f02;0x1f03;0x1ec2;0x1ec7;0x1e84;0x1e87;0x1e89;0x1e81;0x1e82;0x1e04;0x1e07;0x1e2d;0x1e2e;0x1e09;0x1e02;0x1e03;0x1f04;0x21c2;0x2183;0x1f81;0x233d;0x2342;0x2345;0x2336;0x2324;0x2330;0x2331;0x2337;0x2339;0x233a;0x2313;0x2322;0x2321;0x2343;0x2302;0x25bb;0x25b9;0x25ba;0x25bc;0x25bd;0x25b5;0x25b8;0x24b8;0x24b9;0x24ba;0x24bb;0x2438;0x24b6;0x24b7;0x25e0;0x25e2;0x25e5;0x25a6;0x25a7;0x25a9;0x25aa;0x2563;0x25a0;0x2561;0x2560;0x2523;0x2521;0x25a2;0x25a5;0x25ab;0x2420;0x249c;0x249d;0x24dd;0x24dc;0x2520;0x24e0;0x2460;0x24df;0x24a4;0x249f;0x25ac;0x25ec;0x25b6;0x24b0;0x24b1;0x2232;0x2233;0x2238;0x2235;0x2236;0x2237;0x2230;0x2231;0x20b6;0x20b7;0x223f;0x25fa;0x25fb;0x25ad;0x25af;0x2531;0x2571;0x2544;0x2582;0x2583;0x2501;0x2503;0x24c7;0x24c8;0x24c9;0x24bf;0x2482;0x2484;0x2486;0x2487;0x2488;0x2414;0x25a4;0x25a3;0x2483;0x25f9;0x25ed;0x2508;0x2507;0x2509;0x252f;0x2504;0x24ad;0x24af;0x24a0;0x24ac;0x2489;0x248a;0x24fa;0x2207;0x2204;0x2205;0x2206;0x2208;0x2505;0x220a;0x222b;0x222f;0x220d;0x2216;0x2203;0x20f1;0x20f2;0x20f3;0x20f5;0x20f6;0x20fd;0x20be;0x20bf;0x20f0;0x20bb;0x20c2;0x20b8;0x20b9;0x20b5;0x20b0;0x2082;0x20b3;0x20b1;0x20b2;0x20ff;0x20fe;0x20c0;0x20b4;0x2081;0x2200;0x28b8;0x2838;0x27ba;0x27bb;0x2730;0x28e0;0x28e1;0x2820;0x2860;0x28a0;0x28a1;0x2717;0x2757;0x27e0;0x27a0;0x27b7;0x27b8;0x27b0;0x26b1;0x26b2;0x26b5;0x26b8;0x26f5;0x2882;0x2803;0x2805;0x2782;0x2785;0x2786;0x2681;0x2684;0x2704;0x2900;0x2901;0x2920;0x2924;0x2925;0x293d;0x2940;0x2941;0x297e;0x2980;0x29bb;0x29bc;0x29c0;0x29f1;0x2b00;0x2b85;0x2b87;0x2b8c;0x2bb1;0x2bb2;0x2bb3;0x2bb4;0x2bb5;0x2bb9;0x2bbc;0x2c02;0x2c05;0x2c18;0x2c19;0x2c2c;0x2c31;0x2c33;0x2c34;0x2c38;0x2c39;0x2c3a;0x2c58;0x2c59;0x2c77;0x2c79;0x2d04;0x2d05;0x2d18;0x2d19;0x2d2c;0x2d30;0x2d39;0x2d58;0x2d59;0x2d79;0x2d83;0x2d98;0x2db8;0x2db9;0x2dd8;0x2df9;0x2e12;0x2e2a;0x2f04;0x2f18;0x2f38;0x2f58;0x2f80;0x3180;0x3182;0x31a1;0x31c0;0x31c2;0x31fe;0x3200;0x3224;0x323e;0x3340;0x2685;0x2689;0x26af;0x26b3;0x26b7;0x26b9;0x26ba;0x26bb;0x2702;0x27030x2705;0x2709;0x2770;0x2783;0x2788;0x27b1;0x27b2;0x27b6;0x27fa;0x27fb;0x2808;0x2822;0x2878;0x28a3;0x28b0;0x28b9;0x28ba;0x28bb;0x28e3;0x28f8"
    ["$NV_DRIVER_G07"]="" # Driver not yet in repos. As soon as this is wired up Turing and newer goes here eg. G06-open
)


enable_mok_autostart(){
    echo -e "[Desktop Entry]\nExec=/usr/bin/kalpa-driver-manager --mok\nType=Application" > "$AUTOSTART_FILE"
}

clear_mok_autostart(){
    if [[ -f "$AUTOSTART_FILE" ]]; then
        rm -f "$AUTOSTART_FILE"
    fi
}

enable_validate_autostart(){
        echo -e "[Desktop Entry]\nExec=/usr/bin/kalpa-driver-manager --validate\nType=Application" > "$AUTOSTART_VALIDATE_FILE"
}

clear_validate_autostart(){
    if [[ -f "$AUTOSTART_VALIDATE_FILE" ]]; then
        rm -f "$AUTOSTART_VALIDATE_FILE"
    fi
}

enroll_mok(){
    kdesu -t -c "for der_file in /usr/share/nvidia-pubkeys/*; do if [[ -f \"\$der_file\" ]]; then echo \"Enrolling: \${der_file}\" && mokutil -i \"\$der_file\" -p 1234 ; fi ; done" >> "$LOG_FILE"
    enroll_mok_returned=$?
    if [ $enroll_mok_returned == 0 ]; then
        enable_validate_autostart
        kdialog --title "$TITLE" --msgbox "MOKs have been enrolled. After restarting your computer the UEFI will show a dialog called 'Perform MOK management'. In here please choose 'Enroll MOK' -> 'Continue' -> 'Yes' and enter '1234' as password. Afterwards the NVIDIA driver should be loaded.\n\nAttention: After every NVIDIA driver update you have to repeated this process. Simply launch 'kalpa-driver-manager --mok', or right-click the Kalpa Driver Manager in start menu and choose MOK management, to run though this dialog again."
    fi
}

read_nvidia_device_name(){
    stripped_device_id=${found_nvidia_device:2:5}
    stripped_vendor_id=${NVIDIA_VENDOR_ID:2:5}
    echo "$(lspci -d $stripped_vendor_id:$stripped_device_id)"
}

detect_power(){
    if [ ! systemd-ac-power ]; then
        is_on_battery=true
    fi
    if [ $(powerprofilesctl get) == "power-saver" ]; then
        is_power_saving=true
    fi
}

# Scans all PCI devices for vendor NVIDIA
# If NVIDIA devices found checks if they are of type GPU
# If there are NVIDIA GPUs check if they are supported by any known driver as defined in the GPU_SUPPORT_MATRIX
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
                            fi
                        done
                    done
                fi
            done
        fi
    done
}

detect_nvidia_driver_running(){
    for module in ${NVIDIA_DRIVER_MODULES[@]}; do
        if [ ! $(lsmod | grep -om1 $module) ]; then
            return 1 # false
        fi
    done
    return 0 # true
}

detect_secureboot_state(){
    if  detect_binary "mokutil"; then
        while IFS= read -r line ; do
            if [ "$line" == "SecureBoot enabled" ]; then
                is_secure_boot_enabled=true
            fi
        done < <(mokutil --sb-state)
    fi
}

detect_distribution(){
    while IFS= read -r line ; do
        if [ "$line" == "ID=\"kalpa-desktop\"" ] || [ "$line" == "ID=\"opensuse-microos\"" ]; then
            is_distro_supported=true
        fi
    done < <(cat /etc/os-release)
}

detect_binary(){
    return $(command -v "$1" >/dev/null 2>&1)
}

detect_binaries(){
    for binary in ${required_binaries[@]}; do
        if ! detect_binary "$binary"; then
            missing_binaries+=("$binary")
        fi
    done
}

analyze_system(){
    detect_binaries
    detect_distribution
    detect_secureboot_state
    detect_nvidia_gpu_and_supported_driver
    detect_power
}

verify_ready_for_driver(){
    if [ $found_nvidia_device != "none" ]; then
        if ! detect_nvidia_driver_running; then
            is_system_ready_for_nvidia=true
        fi
    fi

    if [ $is_system_ready_for_nvidia = false ]; then
        kdialog --title "$TITLE" --msgbox "All drivers for this system seem to be installed and running."
        exit 1
    fi
}

verify_system(){
    if [ ${#missing_binaries[@]} -ne 0 ]; then
        missing_binaries_string=""
        for missing_bin in ${missing_binaries}; do
            missing_binaries_string+="$missing_bin, "
        done
        message="We couldn't detect the following binaries: $missing_binaries_string this tool is only t be used on Kalpa Desktop."
        if detect_binary "kdialog" ; then
            kdialog --title "$TITLE" --sorry "$message"
        elif detect_binary "zenity"; then
            zenity --error --title "$TITLE" --text "$message"
        else
            echo "$message"
        fi
        exit 1
    else
        verify_ready_for_driver
    fi
}

power_mode_consent(){
    if [ $is_on_battery = true ] || [ $is_power_saving = true ]; then
        case $supported_driver_series in
            "$NV_DRIVER_G06_CLOSED")
                if ! kdialog --title "$TITLE" --yesno "Kalpa detected your system is running on battery or in power saving mode while your GPU requires the closed source NVIDIA kernel modules. Installing these modules requires a substantial amount of energy as they have to be build locally on your machine for the currently running Linux kernel. It is recommended to connect the system to an external power source first or disabling the power save mode to speed up the module compilation. Do you wish to continue anyway?"; then
                    exit 1
                fi
            ;;
        esac
    fi
}

user_consent(){
    kdialog --title "$TITLE" --msgbox "This tool will setup and install the proprietary NVIDIA driver.\n➡️ Using this utility comes with absolutely no warranty use it on your own risk.\n➡️ The driver is not developed by Kalpa, using it is on your own risk.\n➡️ Any driver specific errors are to be reported directly to NVIDIA.\n➡️ By continuing you agree to the NVIDIA Driver License Agreement which can be found here: https://www.nvidia.com/en-us/drivers/nvidia-license/linux/"

    if kdialog --title "$TITLE" --yesno "Do you accept the NVIDIA Driver License Agreement?"; then
        user_agreed_to_license=true
    fi
}

setup_zypper(){
    kdesu -c "sed -i 's/# autoAgreeWithLicenses = no/autoAgreeWithLicenses = yes/' \"/etc/zypp/zypper.conf\""
}

setup_transactional_update(){
    kdesu -c "echo \"ZYPPER_AUTO_IMPORT_KEYS=1\" > \"/etc/transactional-update.conf\""
}

setup_g06_open_driver(){
    kdesu -t -c "transactional-update -n pkg in openSUSE-repos-MicroOS-NVIDIA && transactional-update -c -n pkg in nvidia-open-driver-G06-signed-kmp-meta && transactional-update apply && version=\$(rpm -qa --queryformat '%{VERSION}\n' nvidia-open-driver-G06-signed-kmp-default | cut -d \"_\" -f1 | sort -u | tail -n 1) && transactional-update -n -c pkg in nvidia-compute-utils-G06 == \$version nvidia-persistenced == \$version nvidia-video-G06 == \$version && transactional-update -c initrd" >> "$LOG_FILE"
}

setup_g06_closed_driver(){
    kdesu -t -c "transactional-update -n pkg in openSUSE-repos-MicroOS-NVIDIA && transactional-update -n -c pkg in nvidia-driver-G06-kmp-meta && transactional-update -c initrd" >> "$LOG_FILE"
}

do_install_nvidia_drivers(){
    if kdialog --title "$TITLE" --yesno "Kalpa will install driver series $supported_driver_series for your device:\n$(read_nvidia_device_name) ($found_nvidia_device)"; then
        current_install_step=0

        dbusRef=`kdialog --title "$TITLE" --progressbar "Setup Kalpa Desktop, please stand by ..." 3`
        qdbus6 $dbusRef showCancelButton false


        qdbus6 $dbusRef setLabelText "Configure zypper..."
        setup_zypper
        ((current_install_step++))
        qdbus6 $dbusRef Set "" value $current_install_step

        qdbus6 $dbusRef setLabelText "Configure transactional-update..."
        setup_transactional_update
        ((current_install_step++))
        qdbus6 $dbusRef Set "" value $current_install_step

        qdbus6 $dbusRef setLabelText "Installing NVIDIA driver..."
        case $supported_driver_series in
            "$NV_DRIVER_G06_CLOSED")
                qdbus6 $dbusRef setLabelText "Installing NVIDIA driver, this will take some time..."
                setup_g06_closed_driver
                install_returned=$?
            ;;
            "$NV_DRIVER_G06_OPEN")
                setup_g06_open_driver
                install_returned=$?
            ;;
        esac
        ((current_install_step++))
        qdbus6 $dbusRef Set "" value $current_install_step

        qdbus6 $dbusRef close

        if [ $install_returned == 0 ]; then
            if [ $is_secure_boot_enabled = true ] && [ $supported_driver_series == "$NV_DRIVER_G06_CLOSED" ]; then
                enable_mok_autostart
                kdialog --title="$TITLE" --msgbox "Driver installation successful. However we detected SecureBoot is enabled while also installing the closed source NVIDIA Kernel module. In order for the driver to actual function we have to enroll the required SecureBoot signing keys for the driver. After rebooting $TITLE will open up and guide you through the process."
            else
                enable_validate_autostart
                kdialog --title="$TITLE" --msgbox "Installation successful, please reboot your computer any time for the driver to load up."
            fi
        else
            kdialog --title="$TITLE" --sorry "There seemed to be an error during the driver installation. Please submit this error to Kalpa Desktop and attache this log file to the report $LOG_FILE"
        fi
    fi
}

read_commandline(){
    for i in "$@"; do
        case $i in
            -m*|--mok*)
            analyze_system
            verify_system
            if [ $is_secure_boot_enabled = true ]; then
                if [ $supported_driver_series == "$NV_DRIVER_G06_CLOSED" ]; then
                    if kdialog --title "$TITLE" --yesno "Welcome to the MOK enroll assistant. By continuing we will modify your systems SecureBoot setup by adding the NVIDIA provided signing Key to the UEFI keystore. Do you wish to continue?"; then
                        enroll_mok
                    fi
                else
                    kdialog --title "$TITLE" --msgbox "Enrolling signing keys is not required on this system. Your GPU is supported by the open source NVIDIA kernel module which do not require the enrollment of singing keys."
                fi
            else
                kdialog --title "$TITLE" --msgbox "Enrolling signing keys is not required on this system. SecureBoot is disabled"
            fi
            clear_mok_autostart
            ;;
            --validate*)
                analyze_system
                if detect_nvidia_driver_running; then
                    clear_validate_autostart
                else
                    kdialog --title "$TITLE" --sorry "It seems the NVIDIA drivers couldn't be loaded despite the installation looked to be done successful. Please report this error to Kalpa Desktop and attach $LOG_FILE so we can investigate."
                    clear_validate_autostart
                fi
            ;;
            *)
                # Unknonw option
            ;;
        esac
    done
}

main(){
    analyze_system
    verify_system
    power_mode_consent
    user_consent

    if [ $user_agreed_to_license = true ]; then
        case $supported_driver_series in
            "$NV_DRIVER_G00"|"$NV_DRIVER_G04"|"$NV_DRIVER_G05")
                kdialog --title "$TITLE" --sorry "Kalpa detected a NVIDIA GPU (Device ID: $found_nvidia_device) but it is not considered to deliver a good experience. If you believe this to be a mistake please check your graphics card at: https://www.nvidia.com/en-us/drivers/. If the minimum supported driver series is 500 or newer please report this issue to Kalpa Desktop."
            ;;
            "none")
                if kdialog --title "$TITLE" --yesno "Kalpa detected a NVIDIA GPU (Device ID: $found_nvidia_device) but couldn't match it with any supported driver series. We will try to install the latest driver. Do you want to continue?"; then
                    supported_driver_series="$NV_DRIVER_G06_OPEN"
                    do_install_nvidia_drivers
                fi
            ;;
            *)
                do_install_nvidia_drivers
            ;;
        esac
    fi
}

if [ "$#" -eq 0 ]; then
    main
else
    read_commandline $@
fi