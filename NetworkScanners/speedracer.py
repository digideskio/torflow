#!/usr/bin/python
#
# 2009 Mike Perry, Karsten Loesing

"""
Speedracer

Speedracer continuously requests the Tor design paper over the Tor network
and measures how long circuit building and downloading takes.
"""

import socket
from time import time,strftime
import sys
import urllib2
import re
import os
import traceback

sys.path.append("../")
from TorCtl.TorUtil import plog
from TorCtl.TorUtil import meta_port, meta_host, control_port, control_host, tor_port, tor_host

sys.path.append("./libs")
from SocksiPy import socks

user_agent = "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; .NET CLR 1.0.3705; .NET CLR 1.1.4322)"

# Some constants for measurements
url = "https://svn.torproject.org/svn/tor/trunk/doc/design-paper/tor-design.pdf"
start_pct = 0
stop_pct = 78
# Slice size:
pct_step = 3
# Number of fetches per slice:
count = 250
save_every = 10

class MetatrollerException(Exception):
    "Metatroller does not accept this command."
    pass

# Connector to the metatroller
class MetatrollerConnector:

    def __init__(self, host, port):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.connect((host, port))
        self.buffer = self.sock.makefile('rb')

    def send_command_and_check(self, line):
        self.sock.send(line + '\r\n')
        reply = self.readline()
        if reply[:3] != '250':
            plog('ERROR', reply)
            raise MetatrollerException(reply)
        return reply

    def readline(self):
        response = self.buffer.readline()
        if not response:
            raise EOFError
        elif response[-2:] == '\r\n':
            response = response[:-2]
        elif response[-1:] in '\r\n':
            response = response[:-1]
        return response 

def get_exit_node(meta):
    ''' ask metatroller for the last exit used '''
    reply = meta.send_command_and_check("GETLASTEXIT")
    p = re.compile('250 LASTEXIT=[\S]+')
    m = p.match(reply)
    exit_node = m.group()[13:]
    plog('DEBUG', 'Current node: ' + exit_node)
    return exit_node


def http_request(address):
    ''' perform an http GET-request and return 1 for success or 0 for failure '''

    request = urllib2.Request(address)
    request.add_header('User-Agent', user_agent)

    try:
        reply = urllib2.urlopen(request)
        decl_length = reply.info().get("Content-Length")
        read_len = len(reply.read())
        plog("DEBUG", "Read: "+str(read_len)+" of declared "+str(decl_length))
        return 1
    except (ValueError, urllib2.URLError):
        plog('ERROR', 'The http-request address ' + address + ' is malformed')
        return 0
    except (IndexError, TypeError):
        plog('ERROR', 'An error occured while negotiating socks5 with Tor')
        return 0
    except KeyboardInterrupt:
        raise KeyboardInterrupt
    except:
        plog('ERROR', 'An unknown HTTP error occured')
        traceback.print_exc()
        return 0 

def speedrace(meta, skip, pct):

    meta.send_command_and_check('PERCENTSKIP ' + str(skip))
    meta.send_command_and_check('PERCENTFAST ' + str(pct))

    attempt = 0
    successful = 0
    while successful < count:
        meta.send_command_and_check('NEWNYM')
        
        attempt += 1
        
        t0 = time()
        ret = http_request(url)
        delta_build = time() - t0
        if delta_build >= 550.0:
            plog('NOTICE', 'Timer exceeded limit: ' + str(delta_build) + '\n')

        build_exit = get_exit_node(meta)
        if ret == 1:
            successful += 1
            plog('DEBUG', str(skip) + '-' + str(pct) + '% circuit build+fetch took ' + str(delta_build) + ' for ' + str(build_exit))
        else:
            plog('DEBUG', str(skip) + '-' + str(pct) + '% circuit build+fetch failed for ' + str(build_exit))

        if ret and successful and (successful % save_every) == 0:
          race_time = strftime("20%y-%m-%d-%H:%M:%S")
          meta.send_command_and_check('CLOSEALLCIRCS')
#          meta.send_command_and_check('SAVESTATS '+os.getcwd()+'/data/speedraces/stats-'+str(skip)+':'+str(pct)+"-"+str(successful)+"-"+race_time)
#          meta.send_command_and_check('SAVERATIOS '+os.getcwd()+'/data/speedraces/ratios-'+str(skip)+':'+str(pct)+"-"+str(successful)+"-"+race_time)
          meta.send_command_and_check('SAVESQL '+os.getcwd()+'/data/speedraces/sql-'+str(skip)+':'+str(pct)+"-"+str(successful)+"-"+race_time)
          meta.send_command_and_check('COMMIT')

    plog('INFO', str(skip) + '-' + str(pct) + '% ' + str(count) + ' fetches took ' + str(attempt) + ' tries.')

def main(argv):
    # establish a metatroller connection
    plog('INFO', 'Connecting to metatroller...')
    try:
        meta = MetatrollerConnector(meta_host, meta_port)
    except socket.error:
        plog('ERROR', 'Couldn\'t connect to metatroller. Is it on?')
        exit()

    # skip two lines of metatroller introduction
    meta.readline()
    meta.readline()
        
    # configure metatroller
    commands = [
        'SQLSUPPORT sqlite:///'+os.getcwd()+'/data/speedraces/speedracer.sqlite',
        'PATHLEN 2',
        'UNIFORM 1',
        'ORDEREXITS 0',
        'USEALLEXITS 0',
        'GUARDNODES 0']
    plog('INFO', 'Executing preliminary configuration commands')
    for c in commands:
        meta.send_command_and_check(c)

    # set SOCKS proxy
    socks.setdefaultproxy(socks.PROXY_TYPE_SOCKS5, tor_host, tor_port)
    socket.socket = socks.socksocket

    while True:
      pct = start_pct
      plog('INFO', 'Beginning time loop')
      
      while pct < stop_pct:
          meta.send_command_and_check('RESETSTATS')
          meta.send_command_and_check('COMMIT')
          plog('DEBUG', 'Reset stats')

          speedrace(meta, pct, pct + pct_step)

          plog('DEBUG', 'speedroced')
          meta.send_command_and_check('CLOSEALLCIRCS')
#          meta.send_command_and_check('SAVESTATS '+os.getcwd()+'/data/speedraces/stats-'+str(pct) + ':' + str(pct + pct_step)+"-"+str(count)+"-"+strftime("20%y-%m-%d-%H:%M:%S"))
#          meta.send_command_and_check('SAVERATIOS '+os.getcwd()+'/data/speedraces/ratios-'+str(pct) + ':' + str(pct + pct_step)+"-"+str(count)+"-"+strftime("20%y-%m-%d-%H:%M:%S"))
          meta.send_command_and_check('SAVESQL '+os.getcwd()+'/data/speedraces/sql-'+str(pct) + ':' + str(pct + pct_step)+"-"+str(count)+"-"+strftime("20%y-%m-%d-%H:%M:%S"))
          plog('DEBUG', 'Wrote stats')
          pct += pct_step
          meta.send_command_and_check('COMMIT')

# initiate the program
if __name__ == '__main__':
    try:
        main(sys.argv)
    except KeyboardInterrupt:
        plog('INFO', "Ctrl + C was pressed. Exiting ... ")
        traceback.print_exc()
    except Exception, e:
        plog('ERROR', "An unexpected error occured.")
        traceback.print_exc()
