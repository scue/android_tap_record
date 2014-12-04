#!/bin/bash - 
#===============================================================================
#
#          FILE: playback.sh
# 
#         USAGE: ./playback.sh 
# 
#   DESCRIPTION: 把 ./recorder.sh 录制的内容输出成一个 send.sh 和 send.c 供回放
#                脚本唯一不好的地方：mindiff=0.1 此值并不代表所有操作的真实场景
#                详情请看脚本 TODO
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: lwq (28120), scue@vip.qq.com
#  ORGANIZATION: 
#       CREATED: Friday, December 05, 2014 12:30:37 CST CST
#      REVISION:  ---
#===============================================================================

file=${1:-"record_stuff.txt"}                   # origin

afile=tmp_a.txt                                 # tmp
ofile=tmp_o.txt                                 # 保存操作
tfile=tmp_t.txt                                 # 保存时间
t1file=tmp_t1.txt                               # times tmp
tcfile=tmp_c.c                                  # 临时C语言文件

modelcfile=model_send.c                         # 模板C语言文件

send=send.sh                                    # 目标脚本文件
targetcfile=send.c                              # 目标C语言文件 --> 最终文件

sleep_arry_line=()                              # 有睡眠操作的sentevent
sleep_arry_time=()                              # 保存睡眠时间

#-------------------------------------------------------------------------------
#  函数: 获得触屏输入设备
#  返回: 触屏输入设备 /dev/event/inputX
#-------------------------------------------------------------------------------
get_touch_device(){
    adb shell getevent -pl|sed -e ':a;N;$!ba;s/\n / /g'|\
        grep 'ABS_MT_TOUCH'|awk '{print $4}'|tr -d '\011\012\015'
}

#-------------------------------------------------------------------------------
#  函数: 比较两个 Float 数值
#-------------------------------------------------------------------------------
compare_float(){
    local a=$1
    local b=$2
    awk -va=$a -vb=$b 'BEGIN {if(a>b) printf("true"); else printf("false")}'
}

#-------------------------------------------------------------------------------
#  函数: 检查元素是否在数组
#-------------------------------------------------------------------------------
containsElement () {
    local e
    for e in "${@:2}"; do
        [[ "$e" == "$1" ]] &&\
            return 0
    done
    return 1
}

touchdev=$(get_touch_device)                    # format: /dev/input/eventX
touchdevs=${touchdev##*/}                       # format: eventX

echo "触屏设备: $touchdev "

# tmp for ofile & tfile
sed 's/\[//g;s/\]//g' $file >$afile             # 删除 '[' 和 ']'

# generate operations to $ofile
# 把sendevent操作输出到文件 $ofile
# 正则解释:
#     1. awk - 转换 第二列 和 第三列 数值为十进制模式(因为ioctl接收的是十进制)
#     2. sed - 4294967295 实为 -1, 原因是-1为0xFFFF,FFFF(4294967295)
#     3. sed - 每行首都插入 'sendevent /dev/input/eventX '
#     4. sed - 替换 'eventX'
cat $afile |\
    awk '{print strtonum("0x"$2), strtonum("0x"$3), strtonum("0x"$4)}' |\
    sed 's/4294967295/-1/g' |\
    sed 's/^/sendevent \/dev\/input\/eventX /g' |\
    sed "s/eventX/$touchdevs/g" >$ofile

# generate times diff, for sleep
# 获取时间差，以区分每个操作事件的sentevent

# 若两个sendevent时间差 < 0.1s 认为在同一个操作内
# 因为一个触屏操作(如点击一下)，需由多个sendevent来组成
# TODO: 这里有一定的人为定义在内，有没有从内核中找到一个准确的时间?
mindiff=0.1

awk '{print $1}' $afile >$t1file                # 抽取时间列，存至 $t1file
tstart=$(sed -n '1p' $t1file)
tend=$(sed -n '$p' $t1file)
tdiff=0
index=1
while read t; do
    case $t in
        $tstart|$tend )                         # 第一个时间和最后一个时间无需比较
            tdiff=0
            ;;
        * )
            prev=$(sed -n "$(($index-1)) p" $t1file)
            tdiff=$(awk -va=$t -vb=$prev 'BEGIN {printf("%lf\n",a-b)}')
            ;;
    esac
    if $(compare_float $mindiff $tdiff); then
        echo ''                                 # 时间差 <0.1s 认为无需sleep
    else
        echo "sleep $tdiff; ${sleep_arry_line[@]}"
        sleep_arry_line+=($index)
        sleep_arry_time+=($(awk -va=$tdiff 'BEGIN {print a*1000000}'))
    fi
    ((index++))
done < $t1file >$tfile

# paste
paste $tfile $ofile >$send                      # 合并两文本，组成 send.sh 脚本
echo "exit" >>$send

# echo "需睡眠行号: ${sleep_arry_line[@]}"
# echo "需睡眠时间: ${sleep_arry_time[@]}"

# 组装成C语言源代码文件
index=1
sleep_arry_time_index=0
>$tcfile
while read line; do                             # 输出临时C语言文件
    type=$(echo $line|awk '{print $3}')
    code=$(echo $line|awk '{print $4}')
    value=$(echo $line|awk '{print $5}')
    if containsElement $index ${sleep_arry_line[@]}; then
        echo "    usleep(${sleep_arry_time[$sleep_arry_time_index]});" >>$tcfile
    fi
cat<<EOF >>$tcfile
    memset(&event, 0, sizeof(event));
    event.type = $type;
    event.code = $code;
    event.value = $value;
    ret = write(fd, &event, sizeof(event));
    if(ret < sizeof(event)) {
        fprintf(stderr, "write event failed, %s\n", strerror(errno));
        return -1;
    }
EOF
    ((index++))
done < $ofile 
append_line=67
sed "$append_line r $tcfile" $modelcfile >$targetcfile
sed -i "s/_REPLACE_DEVICE_/${touchdev//\//\\\/}/g" $targetcfile

echo "使用Shell脚本执行:"
echo "  adb shell < $send >/dev/null"

echo "编译C语言文件执行: (推荐 - 高效, 少差错)"
echo "  arm-linux-androideabi-gcc $targetcfile -o ${targetcfile%.c}"
# 虽然可以使用shell脚本来执行模拟操作，但是Shell脚本执行效率本身比较差，故不推荐
# adb shell <$send >/dev/null

# remove
rm -f $t1file $tfile $ofile $afile $tcfile
#echo "Tips: you can run [ adb shell < $send ] for testing manually."
