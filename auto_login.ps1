$ipAddress = "www.baidu.com"
$pingResult = Test-Connection -ComputerName $ipAddress -Count 1 -Quiet

if ($pingResult) {
    Write-Host "Ping Baidu Success"
} else {
    Write-Host "Ping failed. Disconnecting and reconnecting Wi-Fi..."
    netsh wlan disconnect
    netsh wlan connect name="SUDA_WIFI"
}

Set-Location %脚本目录%
& .\for_suda\Scripts\python.exe .\auto_login.pyw

exit