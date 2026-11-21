# Web 前端镜像：把 Flutter Web 产物与 nginx 配置直接打进镜像，
# 避免 NAS 图形界面部署时相对路径挂载写错导致 403。
FROM nginx:alpine

COPY app/build/web/ /usr/share/nginx/html/
COPY web/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
