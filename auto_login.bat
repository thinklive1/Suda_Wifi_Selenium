netsh wlan disconnect
netsh wlan connect name= SUDA_WIFI
cd %脚本路径%
.\for_suda\Scripts\python.exe .\auto_login.pyw
exit