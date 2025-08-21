#!/bin/bash

# Paths and configurations
TC_DIR="$HOME/android/toolchains/aosp-clang" #clang location
GCC_64_DIR="$HOME/android/toolchains/llvm-arm64" #GCC 64 location
GCC_32_DIR="$HOME/android/toolchains/llvm-arm" #GCC 32 location
AK3_DIR="$HOME/android/Anykernel3" #Anykernel3 location
DEFCONFIG="vendor/ginkgo-perf_defconfig" #Build config location

# Export build metadata
export PATH="$TC_DIR/bin:$PATH"
export KBUILD_BUILD_USER=$(whoami)
export KBUILD_BUILD_HOST=$(hostname)

# Function to handle script cleanup on exit or interrupt
cleanup() {
    echo -e "\nScript interrupted! Performing cleanup..."
    rm -rf out/arch/arm64/boot 2>/dev/null
    echo "Temporary files cleaned up."
    echo "Exiting..."
}

# Set trap to call the cleanup function on ERR or SIGINT (Ctrl+C)
trap cleanup SIGINT ERR

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --regen       Regenerate defconfig and save it to the configuration directory"
    echo "  -c, --clean       Clean the output directory"
    echo "  -g, --get-ksu     Download and set up KernelSU Next, apply patch"
    echo "  -s, --get-susfs   Setup and apply patch for SUSFS (ALWAYS USE WITH -g BECAUSE WITHOUT KERNELSU SCRIPT WILL FAIL!)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "If no options are provided, the script will proceed to compile the kernel and package it."
    echo "The script will also adjust the output ZIP name based on the presence of the KernelSU-Next directory."
    echo ""
    echo "Example:"
    echo "  $0           # Compile kernel"
    echo "  $0 --regen   # Regenerate defconfig"
    echo "  $0 --clean   # Clean output directory"
    echo "  $0 --get-ksu # Download and set up KernelSU Next"
    echo "  $0 --get-ksu --get-susfs # Patch kernel with KernelSU-Next and include SUSFS v1.5.9"
    exit 0
}

# Function to start the timer
start_timer() {
    START_TIME=$(date +%s)  # Get the current time in seconds since epoch
}

# Function to end the timer and display elapsed time
end_timer() {
    END_TIME=$(date +%s)  # Get the end time
    ELAPSED_TIME=$(( END_TIME - START_TIME ))  # Calculate elapsed time in seconds

    # Convert seconds to minutes and seconds
    MINUTES=$(( ELAPSED_TIME / 60 ))
    SECONDS=$(( ELAPSED_TIME % 60 ))

    echo -e "\nCompleted in ${MINUTES} minute(s) and ${SECONDS} second(s)!"
}

# Function to determine the ZIP file name based on the presence of KernelSU and date
get_zip_name() {
    local head date
    head=$(git rev-parse --short=7 HEAD)
    date=$(date +%Y%m%d)  # Get the current date in YYYYMMDD format
  
    if [[ -d "KernelSU" ]]; then
        ZIPNAME="Cryo-ginkgo-ksu-${head}-${date}.zip"
    else
        ZIPNAME="Cryo-ginkgo-${head}-${date}.zip"
    fi

    echo "$ZIPNAME"
}

# Function to download and set up KernelSU Next, apply patch and modify defconfig
set_kernelsu() {
    echo "Downloading and setting up KernelSU..."
    bash ./patch/ksu-next/setup.sh next-susfs-experimental
    if [[ $? -eq 0 ]]; then
        echo "KernelSU-Next downloaded and set up successfully."
        
        if [[ -d "KernelSU-Next" ]]; then
            # Apply KernelSU hook patch
            echo "Applying Scope-Minimal-Hooks_KernelSU-Next.patch..."
            if [[ -f "./patch/Scope-Minimal-Hooks_KernelSU-Next.patch" ]]; then
                if git am ./patch/Scope-Minimal-Hooks_KernelSU-Next.patch; then
                    echo "Patch applied successfully."
                else
                    git am --abort
                    echo "KernelSU-Next (Scope-Minimal-Hooks_KernelSU-Next.patch) PATCH FAILED!"
                    echo "Patching aborted and reverted!"
                    echo 1
                fi
            else
                echo "Patch Scope-Minimal-Hooks_KernelSU-Next.patch not found!"
                exit 1
            fi
            
        else
            echo "KernelSU-Next directory not found after download!"
            exit 1
        fi
    else
        echo "Failed to download KernelSU."
        exit 1
    fi
}

set_susfs() {
    if [[ -d "KernelSU-Next" ]]; then
        # Apply SUSFS patch
        echo "Applying SUSFS_v1.5.9.patch..."
        if [[ -f "./patch/SUSFS_v1.5.9.patch" ]]; then
            if git am ./patch/SUSFS_v1.5.9.patch; then
                echo "Patch applied successfully."
            else
                git am --abort
                echo "SUSFS v1.5.9 (SUSFS_v1.5.9.patch) PATCH FAILED!"
                echo "Patching aborted and reverted!"
                echo 1
            fi
        else
            echo "Patch SUSFS_v1.5.9.patch not found!"
            exit 1
        fi
            
    else
        echo "KernelSU-Next directory not found! Cannot apply SUSFS patch without KernelSU-Next because this have no sense!"
        exit 1
    fi
}


# Function to regenerate defconfig
regen_defconfig() {
    make O=out ARCH=arm64 "$DEFCONFIG" savedefconfig
    cp out/defconfig "arch/arm64/configs/$DEFCONFIG"
    echo "Defconfig regenerated and saved!"
}

# Function to clean the output directory
clean_output() {
    rm -rf out
    echo "Output directory cleaned."
}

# Function to set up output directory and build kernel using a make command stored in an array
setup_and_compile() {
    mkdir -p out
    make O=out ARCH=arm64 "$DEFCONFIG"
    
    echo -e "\nStarting compilation...\n"
    local jobs
    jobs=$(nproc 2>/dev/null || echo 4)

    # Array holding the make arguments
    make_args=(
        -j$((jobs + 1))
        O=out
        ARCH=arm64
        CC=clang
        LD=ld.lld
        AR=llvm-ar
        AS=llvm-as
        NM=llvm-nm
        OBJCOPY=llvm-objcopy
        OBJDUMP=llvm-objdump
        STRIP=llvm-strip
        CROSS_COMPILE="$GCC_64_DIR/bin/aarch64-linux-android-"
        CROSS_COMPILE_ARM32="$GCC_32_DIR/bin/arm-linux-androideabi-"
        CLANG_TRIPLE=aarch64-linux-gnu-
        Image.gz-dtb
        dtbo.img
    )

    # Invoke make with the arguments from the array
    make "${make_args[@]}"
    
    if [[ -f "out/arch/arm64/boot/Image.gz-dtb" && -f "out/arch/arm64/boot/dtbo.img" ]]; then
        echo -e "\nKernel compiled successfully!"
        package_kernel
    else
        echo -e "\nCompilation failed!"
        exit 1
    fi
}

# Function to package kernel into a zip file
package_kernel() {
    local zip_name
    zip_name=$(get_zip_name)
  
    if [[ -d "$AK3_DIR" ]]; then
        cp out/arch/arm64/boot/Image.gz-dtb "$AK3_DIR"
        cp out/arch/arm64/boot/dtbo.img "$AK3_DIR"
        cd "$AK3_DIR" || { echo "Failed to enter AnyKernel3 directory!"; exit 1; }
        
        zip -r9 "../$zip_name" * -x '*.git*' README.md *placeholder
        cd - || exit 1
        
        rm -rf out/arch/arm64/boot
        echo -e "\nKernel packaged successfully as: $zip_name"
        end_timer  # End the timer and display elapsed time
    else
        echo "AnyKernel3 directory not found!"
        exit 1
    fi
}

# Main function to control script flow
main() {
    start_timer

    do_regen=0
    do_clean=0
    do_ksu=0
    do_susfs=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--regen)    do_regen=1 ;;
            -c|--clean)    do_clean=1 ;;
            -g|--get-ksu)  do_ksu=1 ;;
            -s|--get-susfs) do_susfs=1 ;;
            -h|--help)     show_help; exit 0 ;;
            *)             echo "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done

    if [[ $do_susfs -eq 1 && $do_ksu -eq 0 ]]; then
        echo "Option --get-susfs (-s) need be to run with --get-ksu(-g)!."
        exit 1
    fi

    [[ $do_regen -eq 1 ]] && regen_defconfig
    [[ $do_clean -eq 1 ]] && clean_output
    [[ $do_ksu -eq 1 ]] && set_kernelsu
    [[ $do_susfs -eq 1 ]] && set_susfs

    if [[ $do_regen -eq 0 && $do_clean -eq 0 && $do_ksu -eq 0 && $do_susfs -eq 0 ]]; then
        setup_and_compile
    fi
}
# Run the main function
main "$@"
