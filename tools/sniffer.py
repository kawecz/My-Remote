#!/usr/bin/env python3
"""
Sniffer: escuta tudo o que a TV manda pelo WebSocket enquanto você
abre apps manualmente com o controle físico.

Uso:
    python3 tools/sniffer.py

Procure no output por eventos tipo ed.apps.launch, ed.installedApp.get,
ou qualquer JSON que tenha a chave "appId".
"""

import asyncio
import json
import ssl
import websockets

TV_IP = '192.168.1.4'
TV_NAME_BASE64 = 'bXlyZW1vdGU='  # base64 de "myremote"


async def sniffer():
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE

    url = (
        f'wss://{TV_IP}:8002/api/v2/channels/samsung.remote.control'
        f'?name={TV_NAME_BASE64}'
    )

    print(f'Conectando em {TV_IP}...')

    async with websockets.connect(url, ssl=ssl_ctx) as ws:
        await ws.recv()  # handshake
        print('Conectado.')
        print()
        print('=' * 60)
        print('AGORA: abra apps na TV com o controle fisico.')
        print('Sugestao de ordem:')
        print('  1. Netflix   (espera 3s)')
        print('  2. YouTube   (espera 3s)')
        print('  3. Disney+   (espera 3s)')
        print('  4. Prime     (espera 3s)')
        print()
        print('O script vai imprimir tudo o que a TV mandar.')
        print('Aperte Ctrl+C pra sair.')
        print('=' * 60)
        print()

        try:
            while True:
                msg = await asyncio.wait_for(ws.recv(), timeout=300)
                try:
                    parsed = json.loads(msg)
                    event = parsed.get('event', '?')

                    # Cabeçalho destacado pra cada evento
                    print(f'\n>>> EVENT: {event}')

                    # Se o JSON tiver "appId" em qualquer lugar, destaca.
                    raw_str = json.dumps(parsed, ensure_ascii=False)
                    if 'appId' in raw_str or 'app_id' in raw_str:
                        print('    *** CONTÉM appId! ***')

                    # Pretty-print do JSON completo
                    print(json.dumps(parsed, indent=2, ensure_ascii=False))
                    print('-' * 60)

                except json.JSONDecodeError:
                    print(f'\n[raw, não é JSON]\n{msg[:500]}')
                    print('-' * 60)

        except asyncio.TimeoutError:
            print('\nTimeout de 5 min sem mensagens. Encerrando.')
        except KeyboardInterrupt:
            print('\nCtrl+C — encerrando.')


if __name__ == '__main__':
    try:
        asyncio.run(sniffer())
    except KeyboardInterrupt:
        pass