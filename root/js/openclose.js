oc = "open";
function openclose() {
   if (oc == "open") {
      document.getElementById('lock_menu').style.display = 'inline';
      oc = "close";
   } else {
      document.getElementById('lock_menu').style.display = 'none';
      oc = "open";
   }
}
