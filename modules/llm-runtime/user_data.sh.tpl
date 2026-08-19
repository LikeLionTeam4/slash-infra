#!/bin/bash
# cloud-init user_data — 최초 부팅 시 1회만 실행된다. stop/start로는 재실행되지
# 않으므로, EBS에 남은 Ollama 설치·모델을 그대로 두고 재기동만 하면 된다(docs §5-1).
set -euo pipefail

# cloud-init이 이 스크립트를 실행하는 셸엔 $HOME이 비어 있다 — ollama CLI가 모델
# 저장 경로를 정하려고 $HOME을 참조하는데(`ollama pull` 시 "panic: $HOME is not
# defined"), systemd로 도는 ollama 서비스 자체는 자체 유닛의 User=ollama 환경이라
# 영향 없다. root로 pull하는 이 스크립트에서만 명시해주면 된다.
export HOME=/root

curl -fsSL https://ollama.com/install.sh | sh

# 기본값은 127.0.0.1:11434(로컬만 허용)이라 EKS 파드에서 접근이 안 된다 —
# ollama SG가 EKS SG에서만 11434 인바운드를 허용하므로 0.0.0.0으로 바인딩해도
# 외부(인터넷)에는 노출되지 않는다.
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_KEEP_ALIVE=-1"
EOF

# 전용 GPU 인스턴스(gemma3:4b 단독)라 VRAM을 나눠 쓸 다른 워크로드가 없어
# 무기한 유지해도 실질적인 단점이 없다(이슈 #41). API 요청 payload에는 keep_alive를
# 넣지 않는다 — 넣으면 서버 env var보다 우선해서 운영값을 덮어쓸 수 있다.
systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

until curl -sf http://127.0.0.1:11434/api/tags >/dev/null; do
  sleep 2
done

ollama pull ${ollama_model}

# user_data는 최초 부팅 시 1회만 실행되므로 워밍업은 여기서 끝내지 않고, EC2가 매
# stop/start될 때마다 Ollama 기동 후 모델을 VRAM에 올려두는 oneshot 서비스로 등록한다.
cat > /etc/systemd/system/ollama-warmup.service <<EOF
[Unit]
Description=Warm up ${ollama_model} in Ollama after boot
After=ollama.service
Wants=ollama.service

[Service]
Type=oneshot
ExecStartPre=/bin/bash -c 'until curl -sf http://127.0.0.1:11434/api/tags >/dev/null; do sleep 2; done'
ExecStart=/usr/bin/curl -sf http://127.0.0.1:11434/api/generate -d '{"model": "${ollama_model}", "keep_alive": -1}'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ollama-warmup
