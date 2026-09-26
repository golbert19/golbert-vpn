import socket
import select
import threading
import time

LISTENING_PORTS = [80, 8080]
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
BUFLEN = 8192

RESPONSE_101 = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n\r\n"
)

def handler(client_socket, address):
    target_socket = None
    try:
        client_socket.settimeout(10)
        request = b""
        
        while b"\r\n\r\n" not in request and len(request) < BUFLEN:
            data = client_socket.recv(BUFLEN)
            if not data:
                break
            request += data

        if not request:
            client_socket.close()
            return

        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_socket.connect((TARGET_HOST, TARGET_PORT))

        if b'HTTP/' in request or b'GET' in request or b'Upgrade: websocket' in request:
            client_socket.sendall(RESPONSE_101)
        else:
            target_socket.sendall(request)

        client_socket.settimeout(None)
        
        sockets = [client_socket, target_socket]
        while True:
            readable, _, errors = select.select(sockets, [], sockets, 60)
            if errors:
                break
            for s in readable:
                data = s.recv(BUFLEN)
                if not data:
                    return
                if s is client_socket:
                    target_socket.sendall(data)
                else:
                    client_socket.sendall(data)

    except Exception:
        pass
    finally:
        client_socket.close()
        if target_socket:
            try:
                target_socket.close()
            except Exception:
                pass

def server_thread(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', port))
    server.listen(200)
    while True:
        try:
            client, addr = server.accept()
            t = threading.Thread(target=handler, args=(client, addr))
            t.daemon = True
            t.start()
        except Exception:
            pass

if __name__ == '__main__':
    for port in LISTENING_PORTS:
        t = threading.Thread(target=server_thread, args=(port,))
        t.daemon = True
        t.start()
    while True:
        time.sleep(3600)
        
