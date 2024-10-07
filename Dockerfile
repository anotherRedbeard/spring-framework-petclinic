# Use an official Tomcat runtime as a parent image
FROM tomcat:10.1.30-jdk17

# Set the working directory inside the container
WORKDIR /usr/local/tomcat

# Copy the WAR file to the webapps directory of Tomcat
COPY target/petclinic.war /usr/local/tomcat/webapps/

# Expose port 8080 to the outside world
EXPOSE 8080

# Run Tomcat server
CMD ["catalina.sh", "run"]