import psutil
import os
import time
import json
import platform
import subprocess
from datetime import datetime

class SystemMonitor:
    def __init__(self):
        self.script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.logs_dir = os.path.join(self.script_dir, "logs")
        
    def log(self, level, message):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_message = f"[{timestamp}] [{level}] {message}"
        print(log_message)
        
        if self.logs_dir:
            os.makedirs(self.logs_dir, exist_ok=True)
            with open(os.path.join(self.logs_dir, "servertest.log"), "a") as f:
                f.write(log_message + "\n")

    def get_disk_info(self, device):
        if not os.path.exists(device) or not os.path.isblock(device):
            return None
        
        try:
            size_bytes = os.stat(device).st_size
            size_gb = size_bytes // (1024 ** 3)
            
            mounted = False
            with open('/proc/mounts', 'r') as f:
                if any(device in line for line in f):
                    mounted = True
            
            model = ""
            try:
                cmd = ['hdparm', '-I', device]
                output = subprocess.check_output(cmd, stderr=subprocess.PIPE).decode()
                for line in output.split('\n'):
                    if "Model Number:" in line:
                        model = line.split(':', 1)[1].strip()
                        break
            except:
                if device.startswith('/dev/nvme'):
                    try:
                        cmd = ['nvme', 'id-ctrl', device]
                        output = subprocess.check_output(cmd).decode()
                        for line in output.split('\n'):
                            if line.startswith('mn'):
                                model = line.split(':', 1)[1].strip()
                                break
                    except:
                        pass
            
            return {
                'size': size_gb,
                'mounted': mounted,
                'model': model,
                'device': device
            }
        except:
            return None

    def check_disk_health(self, device):
        self.log("INFO", f"Checking health of {device}")
        
        try:
            if "nvme" in device:
                subprocess.check_call(['nvme', 'smart-log', device], 
                                   stdout=subprocess.PIPE, 
                                   stderr=subprocess.PIPE)
            else:
                subprocess.check_call(['smartctl', '-H', device], 
                                    stdout=subprocess.PIPE, 
                                    stderr=subprocess.PIPE)
            return True
        except subprocess.CalledProcessError:
            self.log("ERROR", f"Failed to get health status for {device}")
            return False

    def monitor_system(self, output_dir, interval=10):
        os.makedirs(output_dir, exist_ok=True)
        
        with open(os.path.join(output_dir, "cpu.csv"), "w") as f:
            f.write("Timestamp,User%,System%,Idle%\n")
        with open(os.path.join(output_dir, "fan.csv"), "w") as f:
            f.write("Timestamp,FAN1_RPM,FAN2_RPM,FAN3_RPM,FAN4_RPM,FANA_RPM\n")
        with open(os.path.join(output_dir, "mem.csv"), "w") as f:
            f.write("Timestamp,Total_Memory_MB,Used_Memory_MB,Free_Memory_MB,Shared_Memory_MB,Buffer_Cache_MB,Available_Memory_MB\n")
        
        try:
            while True:
                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                
                cpu_times_percent = psutil.cpu_times_percent()
                with open(os.path.join(output_dir, "cpu.csv"), "a") as f:
                    f.write(f"{timestamp},{cpu_times_percent.user},{cpu_times_percent.system},{cpu_times_percent.idle}\n")
                
                mem = psutil.virtual_memory()
                with open(os.path.join(output_dir, "mem.csv"), "a") as f:
                    f.write(f"{timestamp},{mem.total/1024/1024},{mem.used/1024/1024}," + 
                           f"{mem.free/1024/1024},{mem.shared/1024/1024}," +
                           f"{(mem.buffers + mem.cached)/1024/1024},{mem.available/1024/1024}\n")
                
                try:
                    fan_output = subprocess.check_output(['ipmitool', 'sdr', 'type', 'fan'], 
                                                       stderr=subprocess.PIPE).decode()
                    fans = {}
                    for line in fan_output.split('\n'):
                        if 'FAN' in line and 'RPM' in line:
                            fan_name = line.split('|')[0].strip()
                            fan_rpm = line.split('|')[1].strip().split()[0]
                            fans[fan_name] = fan_rpm
                    
                    with open(os.path.join(output_dir, "fan.csv"), "a") as f:
                        f.write(f"{timestamp}")
                        for fan in ['FAN1', 'FAN2', 'FAN3', 'FAN4', 'FANA']:
                            f.write(f",{fans.get(fan, '0')}")
                        f.write("\n")
                except:
                    self.log("WARNING", "Failed to get fan information")
                
                time.sleep(interval)
                
        except KeyboardInterrupt:
            self.log("INFO", "Monitoring stopped")
