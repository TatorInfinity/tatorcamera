#!/bin/bash

#for terminal use and also a camera app shouldnt make my computer heat up to the same as a volcano
CONFIG_FILE="$HOME/.camrecorder_config"
RECORD_PID=""

# Default settings
DEFAULT_OUTPUT_FOLDER="$HOME/recordings"
DEFAULT_AUDIO_DEVICE=""
DEFAULT_VIDEO_DEVICE="/dev/video0"
DEFAULT_VIDEO_RESOLUTION="640x480"
DEFAULT_VIDEO_BITRATE="1000k"

# Current settings (loaded from config or default)
OUTPUT_FOLDER=""
AUDIO_DEVICE=""
VIDEO_DEVICE=""
VIDEO_RESOLUTION=""
VIDEO_BITRATE=""

# Load config or create default config
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        mapfile -t config < "$CONFIG_FILE"

        # Validate output folder: must be absolute and inside $HOME
        if [[ "${config[0]}" == /* ]] && [[ "${config[0]}" == "$HOME"* ]]; then
            OUTPUT_FOLDER="${config[0]}"
        else
            OUTPUT_FOLDER="$DEFAULT_OUTPUT_FOLDER"
        fi

        AUDIO_DEVICE="${config[1]}"
        VIDEO_DEVICE="${config[2]}"
        VIDEO_RESOLUTION="${config[3]}"
        VIDEO_BITRATE="${config[4]}"

        # Create folder if missing
        if [ ! -d "$OUTPUT_FOLDER" ]; then
            echo "⚠️ Output folder '$OUTPUT_FOLDER' missing. Creating..."
            mkdir -p "$OUTPUT_FOLDER"
        fi

        # Validate video device
        if [ -z "$VIDEO_DEVICE" ] || [ ! -e "$VIDEO_DEVICE" ]; then
            VIDEO_DEVICE="$DEFAULT_VIDEO_DEVICE"
        fi

        # Validate resolution format
        if ! [[ "$VIDEO_RESOLUTION" =~ ^[0-9]+x[0-9]+$ ]]; then
            VIDEO_RESOLUTION="$DEFAULT_VIDEO_RESOLUTION"
        fi

        # Validate bitrate format
        if ! [[ "$VIDEO_BITRATE" =~ ^[0-9]+k$ ]]; then
            VIDEO_BITRATE="$DEFAULT_VIDEO_BITRATE"
        fi
    else
        # No config — set defaults and save
        OUTPUT_FOLDER="$DEFAULT_OUTPUT_FOLDER"
        AUDIO_DEVICE="$DEFAULT_AUDIO_DEVICE"
        VIDEO_DEVICE="$DEFAULT_VIDEO_DEVICE"
        VIDEO_RESOLUTION="$DEFAULT_VIDEO_RESOLUTION"
        VIDEO_BITRATE="$DEFAULT_VIDEO_BITRATE"

        mkdir -p "$OUTPUT_FOLDER"
        save_config
    fi

    echo "✅ Loaded config:"
    echo "   Output folder: $OUTPUT_FOLDER"
    echo "   Audio device:  ${AUDIO_DEVICE:-"(none)"}"
    echo "   Video device:  $VIDEO_DEVICE"
    echo "   Resolution:    $VIDEO_RESOLUTION"
    echo "   Bitrate:       $VIDEO_BITRATE"
}

# Save config
save_config() {
    {
        echo "$OUTPUT_FOLDER"
        echo "$AUDIO_DEVICE"
        echo "$VIDEO_DEVICE"
        echo "$VIDEO_RESOLUTION"
        echo "$VIDEO_BITRATE"
    } > "$CONFIG_FILE"
}

# Setters for config values
set_output_folder() {
    echo "Enter output folder path (relative to home or absolute):"
    read -rp "> " input
    if [ -z "$input" ]; then
        echo "⚠️ No input given, output folder unchanged."
        return
    fi

    # Expand relative paths to absolute
    if [[ "$input" != /* ]]; then
        input="$HOME/$input"
    fi

    mkdir -p "$input"
    OUTPUT_FOLDER="$input"
    save_config
    echo "✅ Output folder set to: $OUTPUT_FOLDER"
}

select_audio_device() {
    echo "🔊 Available ALSA devices:"
    arecord -l
    echo "Enter ALSA device (e.g. hw:1,0):"
    read -rp "> " input
    if [ -n "$input" ]; then
        AUDIO_DEVICE="$input"
        save_config
        echo "✅ Audio device set to: $AUDIO_DEVICE"
    else
        echo "⚠️ No input given, audio device unchanged."
    fi
}

select_video_device() {
    echo "📷 Available video devices:"
    ls /dev/video* 2>/dev/null
    echo "Enter video device (e.g. /dev/video0):"
    read -rp "> " input
    if [ -n "$input" ] && [ -e "$input" ]; then
        VIDEO_DEVICE="$input"
        save_config
        echo "✅ Video device set to: $VIDEO_DEVICE"
    else
        echo "❌ Invalid device or no input, video device unchanged."
    fi
}

set_video_resolution() {
    echo "Enter video resolution (e.g. 640x480, 1280x720):"
    read -rp "> " input
    if [[ "$input" =~ ^[0-9]+x[0-9]+$ ]]; then
        VIDEO_RESOLUTION="$input"
        save_config
        echo "✅ Video resolution set to: $VIDEO_RESOLUTION"
    else
        echo "❌ Invalid format, resolution unchanged."
    fi
}

set_video_bitrate() {
    echo "Enter video bitrate (e.g. 500k, 1000k):"
    read -rp "> " input
    if [[ "$input" =~ ^[0-9]+k$ ]]; then
        VIDEO_BITRATE="$input"
        save_config
        echo "✅ Video bitrate set to: $VIDEO_BITRATE"
    else
        echo "❌ Invalid format, bitrate unchanged."
    fi
}

# Start recording with low lag settings
start_recording() {
    if [ -z "$AUDIO_DEVICE" ]; then
        echo "❗ Please select an audio device first."
        return
    fi

    FILE="$OUTPUT_FOLDER/recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"
    echo "🎥 Recording to $FILE"
    echo "Video device: $VIDEO_DEVICE at $VIDEO_RESOLUTION, bitrate $VIDEO_BITRATE"
    echo "Audio device: $AUDIO_DEVICE"

    ffmpeg -f v4l2 -video_size "$VIDEO_RESOLUTION" -framerate 30 -i "$VIDEO_DEVICE" \
           -f alsa -i "$AUDIO_DEVICE" \
           -c:v libx264 -preset ultrafast -crf 28 -b:v "$VIDEO_BITRATE" -threads 1 \
           -c:a aac -b:a 128k -y "$FILE" &

    RECORD_PID=$!
    echo "▶️ Recording started (PID $RECORD_PID)"
}

stop_recording() {
    if [ -n "$RECORD_PID" ]; then
        echo "🛑 Stopping recording..."
        kill "$RECORD_PID"
        RECORD_PID=""
    else
        echo "⚠️ No recording in progress."
    fi
}

monitor_audio() {
    if [ -z "$AUDIO_DEVICE" ]; then
        echo "❗ Please select an audio device first."
        return
    fi
    echo "🔊 Monitoring audio. Press Ctrl+C to stop."
    arecord -D "$AUDIO_DEVICE" -f cd | aplay
}

preview_camera() {
    echo "📺 Previewing camera. Press Q to quit."
    ffplay -f v4l2 -video_size "$VIDEO_RESOLUTION" -framerate 30 -i "$VIDEO_DEVICE" -loglevel quiet
}

show_settings() {
    echo "===== Current Settings ====="
    echo "Output folder:   $OUTPUT_FOLDER"
    echo "Audio device:    ${AUDIO_DEVICE:-"(none)"}"
    echo "Video device:    $VIDEO_DEVICE"
    echo "Video resolution: $VIDEO_RESOLUTION"
    echo "Video bitrate:   $VIDEO_BITRATE"
    echo "============================"
}

# Main menu loop
main_menu() {
    load_config
    while true; do
        echo ""
        echo "===== Tatorcam Menu ====="
        echo "1) Start Recording"
        echo "2) Stop Recording"
        echo "3) Select Audio Device"
        echo "4) Select Video Device"
        echo "5) Set Output Folder"
        echo "6) Set Video Resolution"
        echo "7) Set Video Bitrate"
        echo "8) Preview Camera"
        echo "9) Monitor Audio Level"
        echo "10) Show Current Settings"
        echo "0) Exit"
        echo "==============================="
        read -rp "Choose an option: " choice

        case $choice in
            1) start_recording ;;
            2) stop_recording ;;
            3) select_audio_device ;;
            4) select_video_device ;;
            5) set_output_folder ;;
            6) set_video_resolution ;;
            7) set_video_bitrate ;;
            8) preview_camera ;;
            9) monitor_audio ;;
            10) show_settings ;;
            0) stop_recording; echo "👋 Goodbye!"; exit 0 ;;
            *) echo "❌ Invalid choice." ;;
        esac
    done
}

main_menu

