#!/bin/sh

function optimize
{
    echo $1
    filesize=`stat -f %z "$1"`
    if [[ $filesize -lt 10000 ]]; then
        jpegtran -copy none -optimize "$1" > "$1.bak"
        echo "pet"
    else
        jpegtran -copy none -progressive "$1" > "$1.bak"
        echo "grand"
    fi
    
    if [[ $filesize -lt `stat -f %z "$1.bak"` ]]; then
        echo "compression plus lourde"
        rm "$1.bak"
    else
        echo "good!"
        mv "$1.bak" "$1"
    fi
}

#hugo --source hugo/ --destination ../

# brew install optipng
 find ./hugo/content/posts/fluent-bit-metrics -name "*.png" -exec optipng -o7 {} \;
# find ./hugo/content/posts/skywatcher-direct -name '*.jpg' -type f -print0 |while read -d $'\0' i; do optimize "$i"; done

