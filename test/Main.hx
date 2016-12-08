class Main {

    // Note: debugger crash with "Uncaught exception: Failed to read memory" when test closes
    static function main(){
        while( true ){
            Sys.println(Date.now());
            Sys.stdout().flush();
            Sys.sleep(5);
        }

        
    }
    
}