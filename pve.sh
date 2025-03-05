#!/bin/bash
# Optimized Proxmox VE Installation Script with USTC Mirror Option
# Source: https://github.com/OffroadOps/pve_fast_install_system
# Updated: 2025-03-05

# 项目名称
project_name="pve_fast_install_system"

# 日志文件路径
log_file="./pve_default_generator_$(date +'%Y%m%d_%H%M%S').log"

# 临时解压目录
extract_dir="./System_Files"
mkdir -p "$extract_dir"

# 下载目录
download_dir="./System_OS"
mkdir -p "$download_dir"

# 输出日志
log() {
    echo "$1" | tee -a "$log_file"
}

# 错误退出
error_exit() {
    log "错误: $1"
    exit 1
}

# 下载的 Debian 镜像
debian_versions=(
    "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
    "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
    "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2"
)

# 下载的 Windows 镜像
windows_versions=(
    "cn_win2012r2.xz"
    "cn_win2012r2_uefi.xz"
    "cn_win2016.xz"
    "cn_win2016_uefi.xz"
    "cn_win2019.xz"
    "cn_win2019_uefi.xz"
    "en-us_win10_ltsc_uefi.xz"
    "en-us_win11_ltsc.xz"
    "en-us_win11_ltsc_uefi.xz"
    "en-us_win11_uefi.xz"
    "en-us_win2022.xz"
    "en-us_win2022_uefi.xz"
    "en-us_win2025.xz"
    "en-us_win2025_uefi.xz"
    "en-us_windows10_ltsc.xz"
    "en-us_windows11.xz"
    "en-us_windows11_22h2.xz"
    "en-us_windows11_22h2_uefi.xz"
    "en_win2012r2.xz"
    "en_win2012r2_uefi.xz"
    "en_win2016.xz"
    "en_win2016_uefi.xz"
    "en_win2019.xz"
    "en_win2019_uefi.xz"
    "ja-jp_win10_ltsc_uefi.xz"
    "ja-jp_win11_ltsc.xz"
    "ja-jp_win11_ltsc_uefi.xz"
    "ja-jp_win11_uefi.xz"
    "ja-jp_win2022.xz"
    "ja-jp_win2022_uefi.xz"
    "ja-jp_win2025.xz"
    "ja-jp_win2025_uefi.xz"
    "ja-jp_windows10_ltsc.xz"
    "ja-jp_windows11.xz"
    "ja-jp_windows11_22h2.xz"
    "ja-jp_windows11_22h2_uefi.xz"
    "ja-win2012r2.xz"
)

# 默认配置
default_vm_id="100"
disk_format="qcow2"

# 开始
log "欢迎使用 $project_name"

echo "请选择操作:"
echo "1) 创建虚拟机"
echo "2) 导入虚拟机"
read -p "请输入选项 [1-2]: " action_choice

case $action_choice in
    1)
        log "选择了创建虚拟机"

        # 自动分配 VM ID
        existing_vms=$(qm list | awk '{print $1}' | grep -E '^[0-9]+$' | sort -n)
        new_vm_id=$default_vm_id
        for vm_id in $existing_vms; do
            if [[ $vm_id -ge $new_vm_id ]]; then
                new_vm_id=$((vm_id + 1))
            fi
        done
        log "新虚拟机编号: $new_vm_id"

        echo "请选择 Windows 版本:"
        select win_version in "${windows_versions[@]}"; do
            os_url="https://dl.lamp.sh/vhd/$win_version"
            os_name="$win_version"
            log "选择的 Windows 镜像: $os_url"
            [[ "$win_version" == *"uefi"* ]] && uefi_mode="yes" || uefi_mode="no"
            break
        done

        image_file="${download_dir}/${os_name}"
        extracted_image="${extract_dir}/${os_name%.xz}"

        if [ ! -f "$image_file" ]; then
            log "下载镜像文件: $os_url"
            curl -L "$os_url" -o "$image_file" --progress-bar
            [[ $? -ne 0 || ! -f "$image_file" ]] && error_exit "镜像文件下载失败！"
            log "镜像文件下载成功: $image_file"
        else
            log "镜像文件已存在: $image_file"
        fi

        if [[ "$image_file" == *.xz ]]; then
            if [ ! -f "$extracted_image" ]; then
                log "解压中..."
                xz -d --verbose --keep --stdout "$image_file" > "$extracted_image"
                [[ $? -ne 0 || ! -f "$extracted_image" ]] && error_exit "解压失败！"
                log "解压成功: $extracted_image"
            fi
            image_file="$extracted_image"
        fi

        log "验证解压后的镜像文件..."
        qemu-img info "$image_file" || error_exit "镜像文件损坏或无效"
        log "镜像文件验证通过"

        storage_pool=$(pvesm status | grep "local" | awk '{print $1}' | head -n 1)
        [[ -z "$storage_pool" ]] && error_exit "未找到有效存储池！"
        log "选择存储池: $storage_pool"

        log "创建虚拟机 $new_vm_id"
        qm create "$new_vm_id" --name "vm-${new_vm_id}" --memory 1024 --cores 1 --net0 virtio,bridge=vmbr0
        [[ $? -ne 0 ]] && error_exit "创建虚拟机失败！"

        qm importdisk "$new_vm_id" "$image_file" "$storage_pool" --format "$disk_format"
        log "镜像导入成功"

        qm set "$new_vm_id" --scsihw virtio-scsi-pci --scsi0 "$storage_pool:$new_vm_id/vm-${new_vm_id}-disk-0.qcow2"
        log "磁盘成功添加到虚拟机"

        qm set "$new_vm_id" --boot order=scsi0
        log "设置磁盘为启动盘"

        read -p "是否立即启动虚拟机？(y/n): " boot_vm
        if [[ "$boot_vm" == "y" || "$boot_vm" == "Y" ]]; then
            qm start "$new_vm_id"
            log "虚拟机 $new_vm_id 启动成功"
        fi
        log "虚拟机创建完成！"
        ;;
    *)
        error_exit "无效选择"
        ;;
esac
