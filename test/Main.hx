class Main {

    // Note: debugger crash with "Uncaught exception: Failed to read memory" when test closes
    static function main(){
        while( true ){
            doPrintDate();
            Sys.sleep(2);
            Sys.println('--');
            Sys.stdout().flush();
            Sys.sleep(2);
        }
    }

    static function doPrintDate(){
        printDate();
    }

    static function printDate(){
        Sys.println(Date.now());
    }
    
}