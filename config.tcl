
# expfep configuration file

# fep on/off key
set ::config(active_key) ""
# message when fep is off
set ::config(menu_off_text) "[exec tput rev]^\\[exec tput sgr0] Enable FEP"
# message when fep is on
set ::config(menu_on_text) [string cat \
                           "[exec tput rev]^\\[exec tput sgr0] Disable FEP" \
                           " [exec tput rev]M-1[exec tput sgr0] hiragana" \
                           " [exec tput rev]M-2[exec tput sgr0] katakana" \
                           " [exec tput rev]M-3[exec tput sgr0] cangjie" \
                           " [exec tput rev]M-4[exec tput sgr0] skk-jisyo" \
                              ]
# mode1 command
set ::config(set_mode1) {change_fep_mode "hiragana" "map/ja-hiragana.map" ""}
# mode2 command
set ::config(set_mode2) {change_fep_mode "katakana" "map/ja-katakana.map" ""}
# mode3 command
set ::config(set_mode3) {change_fep_mode "cangjie" "" "dic/cangjie35-jis.dic"}

# mode4 command
set ::config(set_mode4) {change_fep_mode "skk-jisyo" "map/ja-hiragana.map" "dic/skk-jisyo.dic"}
