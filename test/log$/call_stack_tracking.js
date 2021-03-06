function resetPackage() {
    database.run(`
        BEGIN
            dbms_session.reset_package;            
        END;
    `);
}

let getCallStackJsonProcedureName;

function getCallStack() {
    return database.call(`"${getCallStackJsonProcedureName}"`);
}

setup("Create wrapper for LOG$.GET_CALL_STACK to handle associative array argument", function() {

    getCallStackJsonProcedureName = "get_call_stack_" + randomString(15);

    let getCallStackJsonProcedure = readFile("test/sql/get_call_stack_json.sql");

    database.run(`
        BEGIN
            EXECUTE IMMEDIATE '${getCallStackJsonProcedure.replaceAll("'", "''").replace("${getCallStackJsonProcedureName}", getCallStackJsonProcedureName)}';
        END;
    `);

});

suite("Call stack tracking using call", function() {
    
    suite("Empty call stack", function() {
    
        test("Fill call stack on depth 1", function() {
        
            resetPackage();

            database.run(`
                BEGIN
                    log$.call(0, TRUE);                        
                END;
            `);

            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 3,
                        first_tracked_line: 3
                    }
                ],
                p_values: [
                    {}
                ]
            });
        
        });

        test("Fill call stack on depth 3", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    proc1;  
                END;
            `);

            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 15,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 11,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 6,
                        first_tracked_line: 6
                    }
                ],
                p_values: [
                    {},
                    {},
                    {}
                ]
            });
        
        });

        test("Fill call stack on depth 3, hide one level", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(1, TRUE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    proc1;  
                END;
            `);

            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 15,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 11,
                        first_tracked_line: 11
                    }
                ],
                p_values: [
                    {},
                    {}
                ]
            });
        
        });

        test("Fill call stack on depth 3, hide more levels than there are in the stack", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(10, TRUE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    proc1;  
                END;
            `);

            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [],
                p_values: []
            });
        
        });
    
    });

    suite("Stack matches till the actual height", function() {
    
        test("Saved height 3, tracked height 3, actual height 3, two calls, reset top", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(0, TRUE);
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        log$.call(0, TRUE);
                        proc2;
                    END;

                BEGIN
                    log$.call(0, TRUE);    
                    proc1;
                END;
            `);
        
            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 18,
                        first_tracked_line: 17
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 13,
                        first_tracked_line: 12
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 7,
                        first_tracked_line: 7
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {}
                ]
            });

        });

        test("Saved height 3, tracked height 3, actual height 3, two calls, don't reset top", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(0, TRUE);
                        log$.call(0, FALSE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        log$.call(0, TRUE);
                        proc2;
                    END;

                BEGIN
                    log$.call(0, TRUE);    
                    proc1;
                END;
            `);
        
            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 18,
                        first_tracked_line: 17
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 13,
                        first_tracked_line: 12
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 7,
                        first_tracked_line: 6
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {}
                ]
            });

        });

        test("Saved height 3, tracked depth 1, actual height 3, two calls, reset top", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(0, TRUE);
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    proc1;
                END;
            `);
        
            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 16,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 12,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 7,
                        first_tracked_line: 7
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {}
                ]
            });

        });

        test("Saved height 3, tracked depth 1, actual height 3, two calls, don't reset top", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(0, TRUE);
                        log$.call(0, FALSE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    proc1;
                END;
            `);
        
            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 16,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 12,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 7,
                        first_tracked_line: 6
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {}
                ]
            });

        });

        test("Saved height 3, tracked depth 1, actual height 3, two calls on the same line, don't reset top", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(0, TRUE); log$.call(0, FALSE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    proc1;
                END;
            `);
        
            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 15,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 11,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 6,
                        first_tracked_line: 6
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {}
                ]
            });

        });

        test("Saved height 3, tracked depth 1, tracked height 1, actual height 3, two calls, reset top", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(0, TRUE);
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    log$.call(0, TRUE);
                    proc1;
                END;
            `);
        
            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 17,
                        first_tracked_line: 16
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 12,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 7,
                        first_tracked_line: 7
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {}
                ]
            });

        });

        test("Saved height 4, tracked depth 1, actual height 3, one call, reset top", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc3 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc2 IS
                    BEGIN
                        proc3;
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    proc1;
                END;
            `);
        
            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 21,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 17,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 12,
                        first_tracked_line: 12
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {}
                ]
            });

        });

        test("Saved height 4, tracked depth 1, actual height 3, one call, don't reset top", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc3 IS
                    BEGIN
                        log$.call(0, FALSE);
                    END;

                    PROCEDURE proc2 IS
                    BEGIN
                        proc3;
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    proc1;
                END;
            `);
        
            let callStack = getCallStack();

            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 21,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 17,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 12,
                        first_tracked_line: 12
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {}
                ]
            });

        });
        
    });

    suite("Unit doesn't match below the actual height", function() {
    
        test("Saved depth 4, tracked height 4, branch on level 3 on the same line, actual height 5, one call", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc5 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc4 IS
                    BEGIN
                        proc5;
                    END;

                    PROCEDURE proc3 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(0, TRUE);
                        proc3; proc4;
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        log$.call(0, TRUE);
                        proc2;
                    END;

                BEGIN
                    log$.call(0, TRUE);
                    proc1;
                END;
            `);

            let callStack = getCallStack();  
            
            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 33,
                        first_tracked_line: 32
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 28,
                        first_tracked_line: 27
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 22,
                        first_tracked_line: 21
                    },
                    {
                        unit: "__anonymous_block.PROC4",
                        line: 11,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC5",
                        line: 6,
                        first_tracked_line: 6
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {},
                    {},
                    {}
                ]
            });
        
        });

        test("Saved depth 4, tracked height 1, branch on level 3 on the same line, actual height 5, one call", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc5 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc4 IS
                    BEGIN
                        proc5;
                    END;

                    PROCEDURE proc3 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc2 IS
                    BEGIN
                        proc3; proc4;
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    log$.call(0, TRUE);
                    proc1;
                END;
            `);

            let callStack = getCallStack();  
            
            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 31,
                        first_tracked_line: 30
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 26,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 21,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC4",
                        line: 11,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC5",
                        line: 6,
                        first_tracked_line: 6
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {},
                    {},
                    {}
                ]
            });
        
        });
        
    });

    suite("Line doesn't match below the actual height", function() {
    
        test("Saved depth 4, tracked height 4, branch on level 3, actual height 5 one call", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc5 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc4 IS
                    BEGIN
                        proc5;
                    END;

                    PROCEDURE proc3 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc2 IS
                    BEGIN
                        log$.call(0, TRUE);
                        proc3; 
                        proc4;
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        log$.call(0, TRUE);
                        proc2;
                    END;

                BEGIN
                    log$.call(0, TRUE);
                    proc1;
                END;
            `);

            let callStack = getCallStack(); 
            
            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 34,
                        first_tracked_line: 33
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 29,
                        first_tracked_line: 28
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 23,
                        first_tracked_line: 21
                    },
                    {
                        unit: "__anonymous_block.PROC4",
                        line: 11,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC5",
                        line: 6,
                        first_tracked_line: 6
                    }
                ],
                "p_values": [
                    {},
                    {},
                    {},
                    {},
                    {}
                ]
            });

        });

        test("Saved depth 4, tracked height 1, branch on level 3, actual height 5 one call", function() {
        
            resetPackage();

            database.run(`
                DECLARE

                    PROCEDURE proc5 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc4 IS
                    BEGIN
                        proc5;
                    END;

                    PROCEDURE proc3 IS
                    BEGIN
                        log$.call(0, TRUE);
                    END;

                    PROCEDURE proc2 IS
                    BEGIN
                        proc3; 
                        proc4;
                    END;

                    PROCEDURE proc1 IS
                    BEGIN
                        proc2;
                    END;

                BEGIN
                    log$.call(0, TRUE);
                    proc1;
                END;
            `);

            let callStack = getCallStack(); 
            
            expect(callStack).to.eql({
                p_calls: [
                    {
                        unit: "__anonymous_block",
                        line: 32,
                        first_tracked_line: 31
                    },
                    {
                        unit: "__anonymous_block.PROC1",
                        line: 27,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC2",
                        line: 22,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC4",
                        line: 11,
                        first_tracked_line: null
                    },
                    {
                        unit: "__anonymous_block.PROC5",
                        line: 6,
                        first_tracked_line: 6
                    }
                ],
                p_values: [
                    {},
                    {},
                    {},
                    {},
                    {}
                ]
            });

        });
    
    });

});

suite("Call stack tracking using CALL", function() {

    test("Check if CALL resets the top", function() {
    
        resetPackage();

        database.run(`
            DECLARE

                PROCEDURE proc1 IS
                BEGIN
                    log$.call;
                    log$.call;
                END;

            BEGIN
                log$.call;
                proc1;
            END;
        `);

        let callStack = getCallStack();

        expect(callStack).to.eql({
            p_calls: [
                {
                    unit: "__anonymous_block",
                    line: 12,
                    first_tracked_line: 11
                },
                {
                    unit: "__anonymous_block.PROC1",
                    line: 7,
                    first_tracked_line: 7
                }
            ],
            p_values: [
                {},
                {}
            ]
        });
    
    });

    test("Hide one level of the stack", function() {
    
        resetPackage();

        database.run(`
            DECLARE

                PROCEDURE proc1 IS
                BEGIN
                    log$.call(1);
                END;

            BEGIN
                log$.call;
                proc1;
            END;
        `);

        let callStack = getCallStack();

        expect(callStack).to.eql({
            p_calls: [
                {
                    unit: "__anonymous_block",
                    line: 11,
                    first_tracked_line: 11
                }
            ],
            p_values: [
                {}
            ]
        });
    
    });
    
});

teardown("Drop the LOG$.GET_CALL_STACK wrapper", function() {
    
    database.run(`
        BEGIN
            EXECUTE IMMEDIATE '
                DROP PROCEDURE "${getCallStackJsonProcedureName}"
            ';
        END;
    `);

});