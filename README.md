#Android触屏事件录制与回放

通常使用于Android手机终端的自动化测试过程;

它能模拟 input 不能完成的一些事件，如 长按操作;

它能自动化操作你的Android屏幕，一次录制，重复利用; 

# 事件录制

手机通过USB线连接到PC，执行命令

    ./recorder.sh

# 事件回放

依赖于录制输出的文件，最终输出一个C语言文件 send.c;

因为 sendevent 命令行执行效率较低，因此建议使用C语言来操作;

经过测试，使用C语言编译输出的二进制文件模拟触屏事件，效果 prefect;

    ./playback.sh
    arm-linux-androideabi-gcc send.c -o send
    adb push send /data/local/tmp/send
    adb shell su -c busybox chmod 755 /data/local/tmp/send
    adb shell su -c /data/local/tmp/send
