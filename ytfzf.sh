#!/usr/bin/env bash

# YouTube to mpv with fzf script

# Check if required commands are available
for cmd in fzf mpv yt-dlp; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

# Function to search YouTube and display results
youtube_search() {
    local query="$1"
    
    # Create a temporary file to store search results
    local temp_file=$(mktemp)
    
    # Search YouTube and save formatted results
    yt-dlp --no-playlist --flat-playlist \
        --print "%(title)s\t%(id)s\t%(webpage_url)s" \
        "ytsearch10:${query}" 2>/dev/null > "$temp_file"
    
    # Check if we got any results
    if [ ! -s "$temp_file" ]; then
        echo "No results found for: $query"
        rm -f "$temp_file"
        return
    fi
    
    # Use fzf to select a video
    local selection=$(cat "$temp_file" | \
        fzf --delimiter='\t' \
            --with-nth=1 \
            --preview='echo "Video ID: {2}\nURL: {3}"' \
            --preview-window=right:50%:wrap \
            --height=40% \
            --prompt="Select video > ")
    
    if [ -n "$selection" ]; then
        # Extract the URL (third field)
        local video_url=$(echo "$selection" | cut -f3)
        echo "Playing: $video_url"
        mpv "$video_url"
    fi
    
    # Clean up
    rm -f "$temp_file"
}

youtube_search_v2() {
    local query="$1"
    
    # Get search results in JSON format for reliable parsing
    local results=$(yt-dlp --no-playlist --flat-playlist -J \
        "ytsearch10:${query}" 2>/dev/null)
    
    if [ -z "$results" ]; then
        echo "No results found for: $query"
        return
    fi
    
    # Parse JSON and create selection list
    local selection=$(echo "$results" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for entry in data.get('entries', []):
    title = entry.get('title', 'Unknown')
    video_id = entry.get('id', '')
    url = entry.get('webpage_url', f'https://www.youtube.com/watch?v={video_id}')
    print(f'{title}\t{video_id}\t{url}')
" 2>/dev/null | \
        fzf --delimiter='\t' \
            --with-nth=1 \
            --preview='echo "Video ID: {2}"' \
            --preview-window=right:40%:wrap \
            --height=40% \
            --prompt="Select video > ")
    
    if [ -n "$selection" ]; then
        local video_url=$(echo "$selection" | cut -f3)
        echo "Playing: $video_url"
        mpv "$video_url"
    fi
}

youtube_search_simple() {
    local query="$1"
    
    # Direct approach: get URLs and titles, let user select
    local selection=$(yt-dlp --no-playlist --flat-playlist \
        --print "%(title)s" \
        --print "%(webpage_url)s" \
        "ytsearch10:${query}" 2>/dev/null | \
        paste - - | \
        fzf --delimiter='\t' \
            --with-nth=1 \
            --preview='echo "URL: {2}"' \
            --preview-window=bottom:20%:wrap \
            --height=40% \
            --prompt="Select video > ")
    
    if [ -n "$selection" ]; then
        local video_url=$(echo "$selection" | cut -f2)
        echo "Playing: $video_url"
        mpv "$video_url"
    fi
}

# Main function
main() {
    echo "YouTube to mpv with fzf"
    echo "Enter a search query or press Ctrl+C to exit"

    while true; do
        read -r -e -p "> " query
        [ -z "$query" ] && continue
        youtube_search_simple "$query"
    done
}

# Run main function
main
