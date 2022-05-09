import "index.css";
import * as Turbo from "@hotwired/turbo";
import * as Honeybader from "@honeybadger-io/js";
Honeybadger.configure({
  apiKey: "HONEYBADGER_API_KEY",
  environment: "HONEYBADGER_ENV",
  revision: "GIT_SHA",
});

// Uncomment the line below to add transition animations when Turbo navigates.
// We recommend adding <meta name="turbo-cache-control" content="no-preview" />
// to your HTML head if you turn on transitions. Use data-turbo-transition="false"
// on your <main> element for pages where you don't want any transition animation.
//
import "./turbo_transitions.js";
Turbo.setProgressBarDelay(50);

// Import all JavaScript & CSS files from src/_components
import components from "bridgetownComponents/**/*.{js,jsx,js.rb,css}";

console.info("Bridgetown is loaded!");
