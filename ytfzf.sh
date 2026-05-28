#!/usr/bin/env bash

# YouTube to mpv with fzf script

# Check if required commands are available
for cmd in fzf mpv yt-dlp; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

# Default resolution (can be changed by user)
DEFAULT_RESOLUTION="1080p"

# Function to set resolution
set_resolution() {
    echo "Current resolution: $DEFAULT_RESOLUTION"
    echo "Select resolution:"
    echo "1) Best available (auto)"
    echo "2) 2160p (4K)"
    echo "3) 1440p (2K)"
    echo "4) 1080p"
    echo "5) 720p"
    echo "6) 480p"
    echo "7) 360p"
    echo "8) Audio only"
    
    read -r -p "Choice (1-8): " choice
    
    case $choice in
        1) DEFAULT_RESOLUTION="best" ;;
        2) DEFAULT_RESOLUTION="2160p" ;;
        3) DEFAULT_RESOLUTION="1440p" ;;
        4) DEFAULT_RESOLUTION="1080p" ;;
        5) DEFAULT_RESOLUTION="720p" ;;
        6) DEFAULT_RESOLUTION="480p" ;;
        7) DEFAULT_RESOLUTION="360p" ;;
        8) DEFAULT_RESOLUTION="audio" ;;
        *) echo "Invalid choice, keeping current resolution: $DEFAULT_RESOLUTION" ;;
    esac
    
    echo "Resolution set to: $DEFAULT_RESOLUTION"
    echo ""
}

# Function to get mpv format string based on user preference
get_format_string() {
    case "$DEFAULT_RESOLUTION" in
        "best")
            echo "bestvideo+bestaudio/best"
            ;;
        "audio")
            echo "bestaudio"
            ;;
        "2160p")
            echo "bestvideo[height<=2160]+bestaudio/bestvideo[height<=2160]/best[height<=2160]/best"
            ;;
        "1440p")
            echo "bestvideo[height<=1440]+bestaudio/bestvideo[height<=1440]/best[height<=1440]/best"
            ;;
        "1080p")
            echo "bestvideo[height<=1080]+bestaudio/bestvideo[height<=1080]/best[height<=1080]/best"
            ;;
        "720p")
            echo "bestvideo[height<=720]+bestaudio/bestvideo[height<=720]/best[height<=720]/best"
            ;;
        "480p")
            echo "bestvideo[height<=480]+bestaudio/bestvideo[height<=480]/best[height<=480]/best"
            ;;
        "360p")
            echo "bestvideo[height<=360]+bestaudio/bestvideo[height<=360]/best[height<=360]/best"
            ;;
        *)
            echo "best"
            ;;
    esac
}

# Function to play video with proper error handling
play_video() {
    local video_url="$1"
    local format_string=$(get_format_string)
    
    echo "Attempting to play with quality: $DEFAULT_RESOLUTION"
    echo "Format string: $format_string"
    
    # Try to play with specified format
    if mpv --ytdl-format="$format_string" "$video_url" 2>/tmp/mpv_error.log; then
        return 0
    else
        echo "Failed to play with selected quality. Trying best available..."
        # Fallback to best available quality
        if mpv --ytdl-format="best" "$video_url" 2>/tmp/mpv_error.log; then
            return 0
        else
            echo "Error playing video. Check /tmp/mpv_error.log for details."
            return 1
        fi
    fi
}

# Function to show available formats for a video
show_formats() {
    local video_url="$1"
    echo "Available formats for this video:"
    yt-dlp --list-formats "$video_url" 2>/dev/null | grep -E "^[0-9]" | head -20
    echo ""
    read -r -p "Enter format code (or press Enter for best): " format_code
    
    if [ -n "$format_code" ]; then
        mpv --ytdl-format="$format_code" "$video_url"
    else
        mpv --ytdl-format="best" "$video_url"
    fi
}

# Function to search YouTube and display results
youtube_search() {
    local query="$1"
    
    echo "Searching YouTube for: $query"
    
    # Direct approach: get URLs and titles, let user select
    local selection=$(yt-dlp --no-playlist --flat-playlist \
        --print "%(title)s" \
        --print "%(webpage_url)s" \
        --print "%(duration)s" \
        --print "%(view_count)s" \
        "ytsearch10:${query}" 2>/dev/null | \
        paste - - - - | \
        awk -F'\t' '{
            # Format duration
            duration = $3
            if (duration != "NA" && duration != "") {
                minutes = int(duration / 60)
                seconds = duration % 60
                duration_str = sprintf("%d:%02d", minutes, seconds)
            } else {
                duration_str = "??:??"
            }
            
            # Format views
            views = $4
            if (views == "NA" || views == "") {
                views_str = "N/A views"
            } else if (views >= 1000000) {
                views_str = sprintf("%.1fM views", views/1000000)
            } else if (views >= 1000) {
                views_str = sprintf("%.1fK views", views/1000)
            } else {
                views_str = views " views"
            }
            
            # Format: Title | Duration | Views | URL
            printf "%-80s\t[%s]\t%s\t%s\n", $1, duration_str, views_str, $2
        }' | \
        fzf --delimiter='\t' \
            --with-nth=1,2,3 \
            --preview='echo -e "Video URL: {4}\n\nPress Enter to play\nPress F for format list\nPress R to change resolution\nEsc to cancel"' \
            --preview-window=bottom:25%:wrap \
            --height=50% \
            --prompt="Search: $query > " \
            --header="Title                                                                                  Duration  Views" \
            --bind='ctrl-r:execute(echo "CHANGE_RES")+abort' \
            --bind='ctrl-f:execute(echo "SHOW_FORMATS")+abort')
    
    # Handle special key bindings
    if [ "$selection" = "CHANGE_RES" ]; then
        set_resolution
        return
    elif [ "$selection" = "SHOW_FORMATS" ]; then
        # This is handled differently - we need the URL
        echo "Please select a video first, then we can show formats"
        sleep 1
        return
    fi
    
    if [ -n "$selection" ]; then
        # Extract the URL (4th field now)
        local video_url=$(echo "$selection" | cut -f4)
        local video_title=$(echo "$selection" | cut -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        echo ""
        echo "Selected: $video_title"
        echo "Quality: $DEFAULT_RESOLUTION"
        echo ""
        echo "Options:"
        echo "  Enter - Play with current quality ($DEFAULT_RESOLUTION)"
        echo "  F     - Show available formats"
        echo "  R     - Change default quality"
        echo "  C     - Cancel"
        echo ""
        
        read -r -p "Choose option (Enter/F/R/C): " play_option
        
        case "$play_option" in
            "F"|"f")
                show_formats "$video_url"
                ;;
            "R"|"r")
                set_resolution
                echo "Playing with new quality: $DEFAULT_RESOLUTION"
                play_video "$video_url"
                ;;
            "C"|"c")
                echo "Cancelled."
                ;;
            *)
                play_video "$video_url"
                ;;
        esac
    else
        echo "No video selected."
    fi
}

# Show current settings and help
show_help() {
    clear
    echo "========================================="
    echo "  YouTube MPV Player with fzf"
    echo "========================================="
    echo ""
    echo "Current default quality: $DEFAULT_RESOLUTION"
    echo ""
    echo "Commands (in main menu):"
    echo "  :res     - Change default video quality"
    echo "  :help    - Show this help message"
    echo "  :exit    - Exit the program"
    echo "  Ctrl+C   - Exit the program"
    echo ""
    echo "During search:"
    echo "  Ctrl+R   - Change quality before selecting"
    echo "  Type     - Filter results by title"
    echo "  Enter    - Select video"
    echo "  Esc      - Cancel search"
    echo ""
    echo "After selection:"
    echo "  Enter    - Play with current quality"
    echo "  F        - Show all available formats"
    echo "  R        - Change quality then play"
    echo "  C        - Cancel and return to search"
    echo ""
    echo "Quality options:"
    echo "  best     - Best available quality"
    echo "  2160p    - Up to 4K"
    echo "  1440p    - Up to 2K"
    echo "  1080p    - Up to Full HD"
    echo "  720p     - Up to HD"
    echo "  480p     - Up to SD"
    echo "  360p     - Low quality"
    echo "  audio    - Audio only"
    echo "========================================="
    echo ""
}

# Main function
main() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║   YouTube MPV Player with fzf         ║"
    echo "║   Quality: $DEFAULT_RESOLUTION                      ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "Type :help for commands, or enter a search query"

    while true; do
        read -r -e -p "Search > " query
        
        # Check for special commands
        case "$query" in
            ":res"|":resolution")
                set_resolution
                clear
                echo "╔════════════════════════════════════════╗"
                echo "║   Quality updated to: $DEFAULT_RESOLUTION              ║"
                echo "╚════════════════════════════════════════╝"
                echo ""
                continue
                ;;
            ":help")
                show_help
                continue
                ;;
            ":exit"|":quit"|":q")
                echo "Goodbye!"
                exit 0
                ;;
            "")
                continue
                ;;
        esac
        
        youtube_search "$query"
        echo ""
        echo "Search again or type :help for options"
        echo ""
    done
}

# Run main function
main
