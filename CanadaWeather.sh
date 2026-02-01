#!/bin/bash
#
# Genmon weather script to fetch Canadian weather data from weather.gc.ca
# Requires: xfce4-genmon-plugin bc curl

### Change these to suit ##############
CITY="Whitby, Ontario"
LAT="43.898"
LON="-78.939"
MOONPHASE_REF_DATE="Jan 21 2023"
MOONPHASE_REF_PERCENT=0
#######################################

# Function to convert Environment Canada icon code to Linux weather icon name
convert_to_linux_icon() {
    local icon_code=$1
    local is_night=$2
    
    case $icon_code in
        00|01|30|31)  # Clear/Sunny
            if [ "$is_night" = "true" ]; then
                echo "weather-clear-night"
            else
                echo "weather-clear"
            fi
            ;;
        02|03|04|32|33|34)  # Partly cloudy / A mix of sun and cloud
            if [ "$is_night" = "true" ]; then
                echo "weather-few-clouds-night"
            else
                echo "weather-few-clouds"
            fi
            ;;
        10)  # Cloudy
            echo "weather-overcast"
            ;;
        05|06|28)  # Mainly cloudy / Increasing cloud
            echo "weather-clouds"
            ;;
        12|13|28|39)  # Rain / Drizzle / Showers
            echo "weather-showers"
            ;;
        09)  # Thunderstorms
            echo "weather-storm"
            ;;
        15|16|17|18|26|27)  # Snow / Flurries / Ice pellets
            echo "weather-snow"
            ;;
        07|14|19)  # Freezing rain / Rain and snow
            echo "weather-showers-scattered"
            ;;
        11)  # Rain showers or flurries
            echo "weather-showers-scattered"
            ;;
        22|23|24|44|45|46|47|48)  # Haze / Smoke / Fog
            echo "weather-fog"
            ;;
        *)  # Default
            echo "weather-severe-alert"
            ;;
    esac
}

# Function to determine if it's nighttime based on sunrise/sunset
is_nighttime() {
    local sunrise_time=$1
    local sunset_time=$2
    
    # Get current time in seconds since epoch
    local current_seconds=$(date +%s)
    
    # Convert sunrise and sunset to seconds since epoch (today's date)
    local sunrise_seconds=$(date -d "$(date +%Y-%m-%d) $sunrise_time" +%s 2>/dev/null)
    local sunset_seconds=$(date -d "$(date +%Y-%m-%d) $sunset_time" +%s 2>/dev/null)
    
    # If conversion failed, fall back to simple hour check
    if [ -z "$sunrise_seconds" ] || [ -z "$sunset_seconds" ]; then
        local hour=$(date +%H)
        if [ $hour -ge 20 ] || [ $hour -lt 6 ]; then
            echo "true"
        else
            echo "false"
        fi
        return
    fi
    
    # Check if current time is before sunrise or after sunset
    if [ $current_seconds -lt $sunrise_seconds ] || [ $current_seconds -gt $sunset_seconds ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to calculate Humidex (Environment Canada formula)
calculate_humidex() {
    local temp=$1
    local dewpoint=$2
    
    # Calculate vapor pressure from dewpoint (in kPa)
    local e=$(echo "scale=4; 6.11 * e(5417.7530 * ((1/273.16) - (1/(273.15 + $dewpoint))))" | bc -l)
    
    # Convert to kPa and calculate humidex
    local e_kpa=$(echo "scale=4; $e / 10" | bc -l)
    local h=$(echo "scale=2; 0.5555 * ($e_kpa - 1.0)" | bc -l)
    local humidex=$(echo "scale=1; $temp + $h" | bc -l)
    
    echo "$humidex"
}

# Function to determine if we should use wind chill (winter months) or humidex (summer months)
is_winter_month() {
    local month=$(date +%m)
    # October(10), November(11), December(12), January(01), February(02), March(03)
    if [ "$month" = "10" ] || [ "$month" = "11" ] || [ "$month" = "12" ] || \
       [ "$month" = "01" ] || [ "$month" = "02" ] || [ "$month" = "03" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to determine "Feels Like" temperature based on season
get_feels_like() {
    local temp=$1
    local wind_chill=$2
    local humidex=$3
	 local final
    
	 # Determine which value to use
    if [ "$(is_winter_month)" = "true" ]; then
        # Winter months: use wind chill if available
        if [ -n "$wind_chill" ]; then
            final=$wind_chill
        else
            final=$temp
        fi
    else
        # Summer months: use humidex if it's significantly different
        if [ -n "$humidex" ] && (( $(echo "$humidex > $temp + 1" | bc -l) )); then
            final=$humidex
        else
            final=$temp
        fi
    fi

	 # 2. Standard Rounding (0.5 rounds up)
    # Adding 0.5 and truncating via 'int' is the standard math approach
    local rounded
    rounded=$(awk "BEGIN {print int($final + ($final >= 0 ? 0.5 : -0.5))}")

    # 3. Pango color coding based on float limits (-15.0 and 29.5)
    if (( $(echo "$final < -14.5" | bc -l) )); then
        echo "<span foreground='#ADD8E6'>$rounded °C</span>" # Light Blue
    elif (( $(echo "$final > 29.5" | bc -l) )); then
        echo "<span foreground='#FF0000'>$rounded °C</span>" # Red
    else
        echo "$rounded" # No color
    fi
}

# Function to calculate moon phase using astronomical algorithm
calculate_moon_phase() {
    # Constants
    local SEC_PER_DAY=86400
    local SYNODIC_SECONDS=2551443

    # Convert Reference date to epoch
    local REF_EPOCH=`date --date "$MOONPHASE_REF_DATE" +%s`

    # Get current epoch
    local NOW_EPOCH=`date +%s`

    # Calculate difference between now and reference
    local SEC_DIFF=$(($NOW_EPOCH - $REF_EPOCH))

    # Calculate Centi-moon value
    local CENTI_MOONS=$((100 * $SEC_DIFF / $SYNODIC_SECONDS))

    # Calculate Moon Percent
    local MOON_PERCENT=$((($CENTI_MOONS + $MOONPHASE_REF_PERCENT) % 100))

    echo "$MOON_PERCENT"
}

# Function to convert moon phase to descriptive text
get_moon_phase_name() {
    local phase=$(echo "scale=2; $1 / 100" | bc -l)
    local phase_pct=$(echo "scale=2; $phase * 100" | bc -l)
    
    # Calculate illumination percentage
    # Illumination is 0% at new moon, 100% at full moon
    local illumination
    if (( $(echo "$phase < 0.5" | bc -l) )); then
        illumination=$(echo "scale=0; $phase * 200" | bc)
    else
        illumination=$(echo "scale=0; (1 - $phase) * 200" | bc)
    fi
    
    MOON_ILLUMINATION="${illumination%.*}"
    
    if (( $(echo "$phase_pct < 6.25" | bc -l) )); then
        echo "🌑 New Moon   <small><span foreground=\"#333333\">( $MOON_ILLUMINATION% illumination )</span></small>"
    elif (( $(echo "$phase_pct < 18.75" | bc -l) )); then
        echo "🌒 Waxing Crescent   <small><span foreground=\"#666666\">( $MOON_ILLUMINATION% illumination )</span></small>"
    elif (( $(echo "$phase_pct < 31.25" | bc -l) )); then
        echo "🌓 First Quarter   <small><span foreground=\"#999999\">( $MOON_ILLUMINATION% illumination )</span></small>"
    elif (( $(echo "$phase_pct < 43.75" | bc -l) )); then
        echo "🌔 Waxing Gibbous   <small><span foreground=\"#cccccc\">( $MOON_ILLUMINATION% illumination )</span></small>"
    elif (( $(echo "$phase_pct < 56.25" | bc -l) )); then
        echo "🌕 Full Moon   <small><span foreground=\"#ffffff\">( $MOON_ILLUMINATION% illumination )</span></small>"
    elif (( $(echo "$phase_pct < 68.75" | bc -l) )); then
        echo "🌖 Waning Gibbous   <small><span foreground=\"#cccccc\">( $MOON_ILLUMINATION% illumination )</span></small>"
    elif (( $(echo "$phase_pct < 81.25" | bc -l) )); then
        echo "🌗 Last Quarter   <small><span foreground=\"#999999\">( $MOON_ILLUMINATION% illumination )</span></small>"
    elif (( $(echo "$phase_pct < 93.75" | bc -l) )); then
        echo "🌘 Waning Crescent   <small><span foreground=\"#666666\">( $MOON_ILLUMINATION% illumination )</span></small>"
    else
        echo "🌑 New Moon   <small><span foreground=\"#333333\">( $MOON_ILLUMINATION% illumination )</span></small>"
    fi
}

# Function to get sunrise/sunset times
get_sun_times() {
	# Fetch the source
	DATA=$(curl -s "https://weather.gc.ca/en/location/index.html?coords=${LAT},${LON}")

	# 1. Extract raw 24-hour times
	RAW_SUNRISE=$(echo "$DATA" | sed -n 's/.*Sunrise:<\/dt><dd[^>]*>\([0-9]\{1,2\}:[0-9]\{2\}\).*/\1/p')
	RAW_SUNSET=$(echo "$DATA" | sed -n 's/.*Sunset:<\/dt><dd[^>]*>\([0-9]\{1,2\}:[0-9]\{2\}\).*/\1/p')

	# 2. Convert to "%l:%M %P" format
	# Note: We add "today" so the date command recognizes it as a time
	SUNRISE=$(date -d "$RAW_SUNRISE today" +"%l:%M %P")
	SUNSET=$(date -d "$RAW_SUNSET today" +"%l:%M %P")
}

# Function to get moon phase information
get_moon_phase() {
    local phase=$(calculate_moon_phase)
    
    if [ -n "$phase" ]; then
        MOON_PHASE=$(get_moon_phase_name "$phase")
    else
        MOON_PHASE=""
        MOON_ILLUMINATION=""
    fi
}

# Get sunrise and sunset times first (needed for nighttime detection)
get_sun_times

# Get moon phase information
get_moon_phase

# Fetch the XML and extract the Current Conditions entry
XML_URL="https://weather.gc.ca/rss/weather/${LAT}_${LON}_e.xml"
WEB_URL="https://weather.gc.ca/en/location/index.html?coords=${LAT},${LON}"

# Fetch the XML once
FORECAST_XML=$(curl -s "$XML_URL")

# Get the active watches and warnings, colour code the ouput strings
WATCHES_ALERTS_TITLE=$(echo "$FORECAST_XML" | awk -F'[<>]' '
/entry/ {
    getline;
    if (match($3, /YELLOW|ORANGE|RED/)) {
        # 1. Capture the color name found
        color_name = substr($3, RSTART, RLENGTH);
        
        # 2. Map color name to Hex
        if (color_name == "RED") hex = "#FF0000";
        else if (color_name == "ORANGE") hex = "#FFA500";
        else if (color_name == "YELLOW") hex = "#FFFF00";

        # 3. Process the text segment
        split($3, a, ",");
        text_out = a[1];
        
        # 4. REMOVE the color name and extra spaces from the output text
        gsub(color_name, "", text_out);
        gsub(/^[ \t]+|[ \t]+$/, "", text_out);
        
        # 5. Output the clean text wrapped in Pango
        printf "<span foreground=\"%s\">%s</span>\n", hex, text_out;
    }
}')

# Extract the Current Conditions entry
CURRENT_CONDITIONS=$(echo "$FORECAST_XML" | \
  awk '/<entry>/ {flag=1; entry=""} 
       flag {entry=entry $0 "\n"} 
       /<\/entry>/ && flag {
         if (entry ~ /Current Conditions/) print entry; 
         flag=0
       }')

# Extract the summary (CDATA content) - handle multiline
SUMMARY=$(echo "$CURRENT_CONDITIONS" | \
  tr '\n' ' ' | \
  sed 's/.*<!\[CDATA\[\(.*\)\]\]>.*/\1/')

# Parse individual fields from the summary
OBSERVED_AT=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Observed at:<\/b>\s*\([^<]*\)<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

CONDITION=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Condition:<\/b>\s*\([^<]*\)<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

TEMPERATURE=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Temperature:<\/b>\s*\([^<]*\)&deg;C<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
TEMPERATURE_ROUNDED=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Temperature:<\/b>\s*\([^<]*\)&deg;C<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
  xargs printf "%.0f")

PRESSURE=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Pressure:<\/b>\s*\([^<]*\)<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

VISIBILITY=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Visibility:<\/b>\s*\([^<]*\)<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

HUMIDITY=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Humidity:<\/b>\s*\([^<]*\)<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

WIND_CHILL=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Wind Chill:<\/b>\s*\([^<]*\)<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

DEWPOINT=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Dewpoint:<\/b>\s*\([^<]*\)&deg;C<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

WIND=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Wind:<\/b>\s*\([^<]*\)<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

AIR_QUALITY=$(echo "$SUMMARY" | \
  sed -n 's/.*<b>Air Quality Health Index:<\/b>\s*\([^<]*\)<br\/>.*/\1/p' | \
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Get Air quality text and colour code ouput
case $AIR_QUALITY in
	0|1|2|3) 	AIR_QUALITY_TEXT="Low Risk" ;;
	4|5|6)   	AIR_QUALITY_TEXT="<span foreground=\"yellow\">Moderate Risk</span>" ;;
	7|8|9|10) 	AIR_QUALITY_TEXT="<span foreground=\"pink\">High Risk</span>" ;;
	*)				AIR_QUALITY_TEXT="<span foreground=\"red\">Very High Risk</span>" ;;
esac

# Calculate Humidex
if [ -n "$TEMPERATURE" ] && [ -n "$DEWPOINT" ]; then
    HUMIDEX=$(calculate_humidex "$TEMPERATURE" "$DEWPOINT")
else
    HUMIDEX=""
fi

# Calculate "Feels Like" temperature based on season
FEELS_LIKE=$(get_feels_like "$TEMPERATURE" "$WIND_CHILL" "$HUMIDEX")

# Fetch the webpage and extract the weather icon
WEATHER_ICON=$(curl -s "$WEB_URL" | \
  grep -o '/weathericons/[0-9]*\.gif' | \
  head -n 1 | \
  sed 's/\/weathericons\///;s/\.gif//')

# Convert to Linux icon name using actual sunrise/sunset times
NIGHT_CHECK=$(is_nighttime "$SUNRISE" "$SUNSET")
LINUX_ICON=$(convert_to_linux_icon "$WEATHER_ICON" "$NIGHT_CHECK")

# Extract all forecast titles and summaries. Get the day from the title and the summary content minus Forcast issued...
ALL_FORECASTS=$(echo "$FORECAST_XML" | tr -d '\n' | \
	sed 's/<entry>/\n<entry>/g' | \
	sed -n 's/.*<title>\([^:]*:\).*<summary[^>]*>\(.*\)<\/summary>.*/<b>\1<\/b> \2/p' | \
	sed 's/&lt;br\/&gt;/ /g' | \
	sed 's/Forecast issued.*$//g' | \
	sed 's/[[:space:]]*$//')

# Get the next 3 day forecasts
DAY_FORECASTS=()
line_num=3  # Start after feed title, alerts, and current conditions

while [ ${#DAY_FORECASTS[@]} -lt 5 ]; do	# get the next 5 summary entries
    forecast=$(echo "$ALL_FORECASTS" | sed -n "${line_num}p")
    DAY_FORECASTS+=("$forecast\n")
    
    line_num=$((line_num + 1))
    
    # Safety break to avoid infinite loop
    if [ $line_num -gt 20 ]; then
        break
    fi
done

# Build tooltip
TOOLTIP="<big><b>${CITY}:\t${TEMPERATURE} °C and ${CONDITION}</b></big>

Feels Like:\t${FEELS_LIKE}"

TOOLTIP="${TOOLTIP}

Air Quality:\t${AIR_QUALITY}   <small>( ${AIR_QUALITY_TEXT} )</small>
Humidity:\t\t${HUMIDITY}
Pressure:\t\t${PRESSURE}
Visibility:\t\t${VISIBILITY}
Wind:\t\t${WIND}

Sunrise:\t\t${SUNRISE}
Sunset:\t\t${SUNSET}

Moon Phase:\t${MOON_PHASE}"

TOOLTIP="${TOOLTIP}

$(printf "%s\n" "${DAY_FORECASTS[@]}")"
if [[ -n "${WATCHES_ALERTS_TITLE}" ]]; then
	TOOLTIP="${TOOLTIP}
<i>${WATCHES_ALERTS_TITLE}
</i>"
fi

TOOLTIP="${TOOLTIP}
<small><i>Observed at: ${OBSERVED_AT}
Source: Weather and Climate Change Canada (weather.gc.ca)</i></small>"

# Output in xfce4-genmon-plugin format
echo "<icon>${LINUX_ICON}</icon>"
echo "<iconclick>xfce-open $WEB_URL</iconclick>"
echo "<txt>${TEMPERATURE_ROUNDED} °C</txt>"
echo -e "<tool>${TOOLTIP}</tool>"
echo "<css>.genmon_imagebutton image {-gtk-icon-transform: scale(1.4);}</css>"

