str=$(lua -e "for i=32,255 do io.write(string.char(i) .. '\n') end")

for file in *.ttf; do
    echo "${str}" | magick -background "rgba(0,0,0,0)" -fill white -font ${file} -pointsize 25 -gravity center label:@- ${file}.png &
done

echo "Done!"
