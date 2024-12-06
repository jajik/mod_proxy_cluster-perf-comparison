/**
 *  Copyright 2017 Ismaïl Senhaji, Guillaume Pythoud
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

package org.example.tomcat.cloud;

import javax.servlet.annotation.WebServlet;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import javax.servlet.http.Cookie;

import java.io.IOException;
import java.io.PrintWriter;
import java.net.InetAddress;

@WebServlet(description = "Demo for sessions in the cloud", urlPatterns = { "/demo" })
public class TestServlet extends HttpServlet {
    private static final String TEMPLATE = "{\n" +
            "  \"counter\": %d,\n" +
            "  \"id\": \"%s\",\n" +
            "  \"new\": %s,\n" +
            "  \"server\": \"%s\",\n" +
            "  \"hostname\": \"%s\",\n" +
            "  \"last\": \"%s\",\n" +
            "  \"newtest\": \"2022\"\n" +
            "}\n";

    @Override
    public void doGet(HttpServletRequest request, HttpServletResponse response) throws IOException, ServletException {
        response.setContentType("application/json;charset=UTF-8");

        HttpSession session = request.getSession();
        Integer counter;
        if (session.isNew()) {
            /* we have a new session */
            counter = 0;
        } else {
            counter = (Integer) session.getAttribute("counter");
            if (counter == null) {
                counter = 0;
            }
            counter++;
            session.setAttribute("counter", counter);
        }

        String id = session.getId();
        String isNew = session.isNew() ? "true" : "false";
        String server = InetAddress.getLocalHost().getHostAddress();
        String hostname = InetAddress.getLocalHost().getHostName();
        String last = session.getLastAccessedTime() + "";

        response.addCookie(new Cookie("JSESSIONID", id));

        try (PrintWriter out = response.getWriter()) {
            out.println(String.format(TEMPLATE, counter, id, isNew, server, hostname, last));
        }
    }
}

