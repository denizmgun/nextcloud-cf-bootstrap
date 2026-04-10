tunnel: {{TUNNEL_ID}}
credentials-file: /root/.cloudflared/{{TUNNEL_ID}}.json

ingress:
  - hostname: {{ADMIN_HOSTNAME}}
    service: https://localhost:8080
    originRequest:
      noTLSVerify: true
  - hostname: {{NC_HOSTNAME}}
    service: http://localhost:11000
  - service: http_status:404
