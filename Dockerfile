FROM nginx:1.13.7-alpine
COPY stage.mustachebash.conf /etc/nginx/conf.d/default.conf
COPY mustachebash.com/dist /dist
COPY mustachebash.com/templates/index.hbs /dist/index.html
