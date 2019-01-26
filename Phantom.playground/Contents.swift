import UIKit

/*:
 # Phantom Types
 
 Consider the following scenario:
 */
func build(_ p1: String, _ p2: String, _ p3: String) -> String {
    return p3 + p1 + p2
}

/*:
 Without context, this doesn't really stop us passing in the values out of order. Or provide us any context as to what the values are meant to be.
 
 One thing you could do to fix the objects where there is a lack of context is to create a Phantom Type.
 
 This is defined as any object that takes a generic that doesn’t appear inside of its constructor.
 
 An example of a Phantom Type is defined below, where A doesn't appear in the constructor:
 */
struct Tagged<A, B> {
    let value: B
    init(_ value: B) {
        self.value = value
    }
}

//: Now we can start defining some more generic types we will want to compose later.
protocol Id { }
protocol Email { }

//: Lets create some Tagged objects for a User.
typealias UserId = Tagged<User, Tagged<Id, Int>>
typealias UserEmail = Tagged<User, Tagged<Email, String>>

struct User {
    let id: UserId
    let email: UserEmail
}

/*:
 With a few small tweaks we now can't pass in any value without it's context.
 
 This can become extremely powerful when we need to ensure we aren't passing values incorrectly and reduce maintenance headaches later on.
 
 However, there is a small problem, our initializer for the above object is now quite complex. Not to mention it's parenthesis hell.
 
 In it's full glory, it looks like this:
*/
let user1 = User(id: UserId(Tagged<Id, Int>(1)), email: UserEmail(Tagged<Email, String>("email@test.com")))

/*:
 We can clean this up a little using .init, but this may just confuse the compiler.
 
 ## Pure
 
 What we really want is a helper function to make this code more readable. Enter `pure`, which is basically a wrapped init.
 
 First, lets define our simple version:
 */
func pure<A, B>(_ x: B) -> Tagged<A, B> {
    return Tagged<A, B>(x)
}

//: This cleans this up so that we can write:
let user2 = User(id: pure(pure(1)), email: pure(pure("email@test.com")))

/*:
 We can still do better though...
 
 Lets create a wrapper for pure(pure) above, I'm going to call it deep, so we don't confuse the compiler too much.
 */
func deep<A, B, C>(_ x: C) -> Tagged<A, Tagged<B, C>> {
    return pure(pure(x))
}

//: We have removed a level of parenthesis now we have something like...
let user3 = User(id: deep(1), email: deep("email@test.com"))

/*:
 That's great, but if we need to do even more operations these can get complex looking again.
 
 Let's introduce some operators to give us some syntactic sugar.
 
 ## Applicative
 
 Applicative or <*> lets us chain functions as we'll see later on:
 */
precedencegroup Applicative {
    associativity: left
}
infix operator <*>: Applicative

/*:
 This operator can be implemented however you want internally, so long as it follows the basic structure laid out in the signature.
 
 Here's an example for Optional:
 */
func <*> <A, B>(f: ((A) -> B)?, x: A?) -> B? {
    return f.flatMap { f in x.map { x in f(x) } }
}

/*:
 ## Currying
 
 Now we can rewrite our create user functionality above with some currying.
 
 We are going to go from (A, B) -> C to (A) -> (B) -> C.
 
 There are libraries out there that create many different levels of this nesting, but I'm just going to implement a rudimentary one for this example.
 */
func curry<A, B, C>(_ f: @escaping (A, B) -> C) -> (A) -> (B) -> C {
    return { a in
        return { b in
            return f(a, b)
        }
    }
}

let createUser = curry(User.init)

//: Now we can add our Applicative (<*>) to inject the values.
let user4 = createUser
    <*> deep(1)
    <*> deep("email@test.com")

/*:
 ## Failability
 
 Now we can go one step further, and introduce the idea of failable initializers.
 
 First, lets define a Result type.
 */
enum Result<E, A> {
    case success(A)
    case error(E)
}

//: Now, we can see this is a Monad. We can map (A) -> B to produce Result<E, B>. So let's implement map:
extension Result {
    func map<B>(_ f: (A) -> B) -> Result<E, B> {
        switch self {
        case let .success(x): return .success(f(x))
        case let .error(e): return .error(e)
        }
    }
}

//: We can also implement flatMap.
extension Result {
    func flatMap<B>(_ f: (A) -> Result<E, B>) -> Result<E, B> {
        switch self {
        case let .success(x): return f(x)
        case let .error(e): return .error(e)
        }
    }
}

//: ...and pure.
func pure<E, A>(_ x: A) -> Result<E, A> {
    return .success(x)
}

/*:
 Nothing revolutionary so far, these are all part of the standard Swift library for things like Array, Optional, etc... and probably Result in Swift 5.
 
 Now lets overload our Applicative.
 */
func <*> <E, A, B>(f: Result<E, (A) -> B>, x: Result<E, A>) -> Result<E, B> {
    return f.flatMap { f in x.map { x in f(x) } }
}

/*:
 ## Compose
 
 In order to deal with function nesting, and remove some parenthesis from our code, lets implement **Compose** or <<<.
 */
precedencegroup Compose {
    associativity: right
    higherThan: Applicative
}
infix operator <<<: Compose

func <<< <A, B, C>(g: @escaping (B) -> C, f: @escaping (A) -> B) -> (A) -> C {
    return { x in g(f(x)) }
}

//: Lets create a helper function to read a value from our nested Tagged objects which will recurse if the value is another Tagged.
extension Tagged {
    func read() -> B {
        return value
    }
    func read<C, D>() -> D where B == Tagged<C, D> {
        return value.read()
    }
}

//: And define some validation rules for the above User object.
typealias ValidationResult<T> = Result<String, T>

func validate(id: UserId) -> ValidationResult<UserId> {
    return id.read() > 0 ? pure(id) : .error("Invalid code")
}

func validate(email: UserEmail) -> ValidationResult<UserEmail> {
    return email.read().contains("@") ? pure(email) : .error("Invalid email")
}

//: Finally, lets create our failable createUser. Note: No need for our `deep` func anymore, the Compose operator <<< handles this for us.
let validateId = validate(id:) <<< pure <<< pure            // (Int) -> ValidationResult<UserId>
let validateEmail = validate(email:) <<< pure <<< pure      // (String) -> ValidationResult<UserEmail>

let userPassingValidation = pure(createUser)
    <*> validateId(1)
    <*> validateEmail("email@test.com")

let userFailingWithInvalidId = pure(createUser)
    <*> validateId(0)
    <*> validateEmail("email@test.com")

let userFailingWithInvalidEmail = pure(createUser)
    <*> validateId(1)
    <*> validateEmail("emailtest.com")

/*:
 There is one, potential problem, what if we want ALL of the issues with this user to be surfaced? i.e. their id and email are invalid.
 
 ## Semigroups
 
 We need to introduce a concept known as a Semigroup, which gives us a new operator <> which usually goes hand in hand with Monoids.
 */
infix operator <>: AdditionPrecedence

protocol Semigroup {
    static func <> (lhs: Self, rhs: Self) -> Self
}

//: We are going to return an array of errors, so extending Array to support this operator will help later.
extension Array: Semigroup {
    static func <> (lhs: Array, rhs: Array) -> Array {
        return lhs + rhs
    }
}

//: We can also extend other types (though not necessary for this example) like follows...
extension String: Semigroup {
    static func <> (lhs: String, rhs: String) -> String {
        return lhs + rhs
    }
}

extension Bool: Semigroup {
    static func <> (lhs: Bool, rhs: Bool) -> Bool {
        return lhs && rhs
    }
}

//: Then we can concatenate them with a reduce.
func concat<S: Semigroup>(_ xs: [S], initial: S) -> S {
    return xs.reduce(initial, <>)
}

//: ^ This concept can bring about some powerful functionality. But that's another subject.

//: Lets overload Applicative again, with a Semigroup requirement and instead of returning a single error, lets combine them.
func <*> <E: Semigroup, A, B>(f: Result<E, (A) -> B>, x: Result<E, A>) -> Result<E, B> {
    switch (f, x) {
    case let (.success(f), _): return x.map(f)
    case let (.error(e), .success): return .error(e)
    case let (.error(e1), .error(e2)): return .error(e1 <> e2)
    }
}

//: With a very small tweak to our above methods we can return an array. Ignore the 'array' prefix/suffix, we only need these because of playgrounds.
typealias ValidationResultArray<T> = Result<[String], T>

func arrayValidate(id: UserId) -> ValidationResultArray<UserId> {
    return id.read() > 0 ? pure(id) : .error(["Invalid code"])
}

func arrayValidate(email: UserEmail) -> ValidationResultArray<UserEmail> {
    return email.read().contains("@") ? pure(email) : .error(["Invalid email"])
}

//: Now we have all the tools we need to handle our multiple error scenario.
let arrayValidateId = arrayValidate(id:) <<< pure <<< pure            // (Int) -> ValidationResult<UserId>
let arrayValidateEmail = arrayValidate(email:) <<< pure <<< pure      // (String) -> ValidationResult<UserEmail>

let userFailingWithInvalidIdAndEmail = pure(createUser)
    <*> arrayValidateId(0)
    <*> arrayValidateEmail("emailtest.com")

//: Great! We receive an array of error strings which we can then use to provide more context to a user.
