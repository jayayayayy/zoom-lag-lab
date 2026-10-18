"""Non-privileged regression checks with mocked PF commands. Does not change networking."""
import os, pathlib, subprocess, tempfile, time
source=(pathlib.Path(__file__).resolve().parent.parent/'lag.sh').read_text()
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d); log=p/'calls'; mock=p/'mock'
 mock.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$CALL_LOG"
case "$*" in
 '-s info')
   if [[ "${PF_ENABLED:-0}" == 1 ]]; then echo 'Status: Enabled'; else echo 'Status: Disabled'; fi
   echo 'current entries 0';;
 '-s rules') echo 'anchor "com.apple/*" all';;
 '-E') echo 'Token : 12345';;
esac
if [[ "$*" == '-X 12345' && "${FAIL_RELEASE:-0}" == 1 ]]; then exit 1; fi
if [[ "$*" == *' -f '* && "$*" != *'/dev/null'* && "$*" != '-n '* && "${FAIL_LOAD:-0}" == 1 ]]; then exit 1; fi
''');mock.chmod(0o755)
 test=source.replace('STATE=/var/run/zoom-lag-lab',f'STATE={p}/state').replace('PF=/sbin/pfctl',f'PF={mock}').replace('[[ $EUID == 0 ]]','[[ 1 == 1 ]]').replace('/sbin/ifconfig "$iface" >/dev/null',':').replace('$(/usr/sbin/sysctl -n net.inet.ip.forwarding)','0').replace('$(/usr/sbin/sysctl -n net.inet6.ip6.forwarding)','0').replace('duration=5','duration=1')
 script=p/'test.sh';script.write_text(test);env=dict(os.environ,CALL_LOG=str(log))
 def run(*args, extra=None):
  argv=list(args)
  if argv and argv[0]=='start' and len(argv)==3:argv.append('timed')
  return subprocess.run(['bash',str(script),*argv],env=dict(env,**(extra or {})),capture_output=True,text=True)
 r=run('start','blackout','en0');assert r.returncode==0,r.stdout+r.stderr
 assert '-X 12345' in log.read_text() and '-f /dev/null' in log.read_text() and not (p/'state').exists()
 print('PASS: bounded session removes rules and releases PF reference')
 r=run('start','blackout','en0',extra={'FAIL_LOAD':'1'});assert r.returncode!=0 and not (p/'state').exists(),r.stdout+r.stderr
 print('PASS: load failure restores PF state')
 assert run('preview','severe','en0;whoami').returncode!=0
 print('PASS: interface injection rejected')
 assert run('stop').returncode==0
 print('PASS: restore without a session is harmless')
 long_script=p/'long.sh';long_script.write_text(test.replace('duration=1','duration=30'))
 def launch(mode='timed', owner='0', target=long_script):
  worker=subprocess.Popen(['bash',str(target),'start','blackout','en0',mode,owner],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  for _ in range(100):
   status=p/'state/status'
   if status.exists() and status.read_text().startswith('active\n'):return worker
   if worker.poll() is not None:raise AssertionError(worker.communicate())
   time.sleep(0.05)
  worker.kill();raise AssertionError('No active status')
 worker=launch();assert (p/'state/status').stat().st_mode & 0o777==0o644
 assert run('status').stdout.startswith('active\n')
 assert run('stop').returncode==0
 worker.communicate(timeout=5);assert not (p/'state').exists()
 print('PASS: progress and early Stop restoration')
 worker=launch();worker.kill();worker.communicate(timeout=5)
 assert (p/'state').exists() and run('stop').returncode==0 and not (p/'state').exists()
 print('PASS: recovery after forcibly terminated worker')
 run('start','blackout','en0',extra={'FAIL_RELEASE':'1'})
 assert (p/'state/status').read_text().startswith('error\n') and (p/'state/token').exists()
 assert run('stop').returncode==0 and not (p/'state').exists()
 print('PASS: incomplete cleanup retains record; retry succeeds')
 log.write_text('');r=run('start','blackout','en0',extra={'PF_ENABLED':'1'})
 assert r.returncode!=0 and not (p/'state').exists() and '-E' not in log.read_text()
 print('PASS: existing enabled PF is refused without mutation')
 log.write_text('');short=p/'burst.sh';short.write_text(test.replace('duration=30','duration=4'))
 r=subprocess.run(['bash',str(short),'start','choppy','en0','timed'],env=env,capture_output=True,text=True)
 assert r.returncode==0,r.stdout+r.stderr
 calls=log.read_text();assert calls.count('-f /dev/null')>=2 and calls.count('-f '+str(p/'state/rules'))>=3
 print('PASS: choppy mode alternates blocking and recovery, then cleans up')

 worker=launch('continuous',target=script)
 time.sleep(1.4)
 assert worker.poll() is None and (p/'state/status').read_text().splitlines()[1]=='0'
 assert run('stop').returncode==0
 worker.communicate(timeout=5);assert not (p/'state').exists()
 print('PASS: continuous mode outlives the timed deadline and stops on request')
 supervisor=subprocess.Popen(['/bin/sleep','30'])
 worker=launch('continuous',owner=str(supervisor.pid))
 supervisor.terminate();supervisor.wait(timeout=3)
 worker.communicate(timeout=5)
 assert worker.returncode==0 and not (p/'state').exists()
 print('PASS: exiting the controlling app automatically restores the connection')
