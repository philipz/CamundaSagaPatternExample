FROM camunda/camunda-bpm-platform:run-7.21.0

USER root
RUN apk add --no-cache git zip
USER camunda
RUN git clone https://github.com/datakurre/camunda-cockpit-plugins.git /camunda/META-INF/resources/webjars/camunda/app/cockpit/scripts/
RUN chown camunda:camunda /camunda/META-INF/resources/webjars/camunda/app/cockpit/scripts/
RUN zip -r internal/webapps/camunda-webapp-webjar-7.15.0.jar META-INF
RUN rm -r META-INF
