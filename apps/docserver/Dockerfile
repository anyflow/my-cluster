FROM nginx:stable

EXPOSE 80

COPY /output/. /usr/share/nginx/html/.

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]