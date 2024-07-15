str=$(lua -e "for i=32,255 do io.write(string.char(i) .. '\n') end")

echo "${str}"
echo "Lua's done it's job"

for file in *.ttf; do
    echo "${str}" | magick -background "rgba(0,0,0,0)" -fill white -font ${file} -pointsize 24 -gravity center label:@- ${file}.png
done
