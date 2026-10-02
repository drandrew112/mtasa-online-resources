-- Name database of the scene peds (English first names). Every live scene ped gets a random
-- one on spawn, picked from the list matching its skin's gender (medsys shows it as the
-- patient name, element data MSM.DATA_NAME).

-- GTA SA / MTA skins that are women. Every other skin counts as a man.
MSM_FEMALE_SKINS = {}
for _, skin in ipairs({
    9, 10, 11, 12, 13, 31, 38, 39, 40, 41, 53, 54, 55, 56, 63, 64, 69, 75, 76, 77, 85, 87, 88,
    89, 90, 91, 92, 93, 129, 130, 131, 138, 139, 140, 141, 145, 148, 150, 151, 152, 157, 169,
    172, 178, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 201, 205, 207, 211, 214, 215,
    216, 218, 219, 224, 225, 226, 231, 232, 233, 237, 238, 243, 244, 245, 246, 251, 256, 257,
    263, 298, 306, 307, 308, 309,
}) do
    MSM_FEMALE_SKINS[skin] = true
end

MSM_NAMES = {
    male = {
        "James", "John", "Robert", "Michael", "William", "David", "Richard", "Joseph", "Thomas",
        "Charles", "Christopher", "Daniel", "Matthew", "Anthony", "Mark", "Donald", "Steven",
        "Paul", "Andrew", "Joshua", "Kenneth", "Kevin", "Brian", "George", "Timothy", "Ronald",
        "Edward", "Jason", "Jeffrey", "Ryan", "Jacob", "Gary", "Nicholas", "Eric", "Jonathan",
        "Stephen", "Larry", "Justin", "Scott", "Brandon", "Benjamin", "Samuel", "Gregory",
        "Alexander", "Frank", "Patrick", "Raymond", "Jack", "Dennis", "Jerry", "Tyler", "Aaron",
        "Henry", "Adam", "Douglas", "Nathan", "Peter", "Zachary", "Kyle", "Walter", "Harold",
        "Jeremy", "Ethan", "Carl", "Keith", "Roger", "Gerald", "Christian", "Terry", "Sean",
        "Arthur", "Austin", "Noah", "Lawrence", "Jesse", "Dylan", "Bryan", "Joe", "Jordan",
        "Billy", "Bruce", "Albert", "Willie", "Gabriel", "Logan", "Alan", "Wayne", "Ralph",
        "Roy", "Eugene", "Randy", "Vincent", "Russell", "Louis", "Philip", "Bobby", "Johnny",
        "Bradley", "Oliver", "Harry", "Luke", "Owen", "Connor", "Liam", "Mason", "Lucas",
    },
    female = {
        "Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica",
        "Sarah", "Karen", "Lisa", "Nancy", "Betty", "Margaret", "Sandra", "Ashley", "Kimberly",
        "Emily", "Donna", "Michelle", "Carol", "Amanda", "Dorothy", "Melissa", "Deborah",
        "Stephanie", "Rebecca", "Sharon", "Laura", "Cynthia", "Kathleen", "Amy", "Angela",
        "Shirley", "Anna", "Brenda", "Pamela", "Emma", "Nicole", "Helen", "Samantha",
        "Katherine", "Christine", "Debra", "Rachel", "Carolyn", "Janet", "Catherine", "Maria",
        "Heather", "Diane", "Ruth", "Julie", "Olivia", "Joyce", "Virginia", "Victoria", "Kelly",
        "Lauren", "Christina", "Joan", "Evelyn", "Judith", "Megan", "Andrea", "Cheryl", "Hannah",
        "Jacqueline", "Martha", "Gloria", "Teresa", "Ann", "Sara", "Madison", "Frances",
        "Kathryn", "Janice", "Jean", "Abigail", "Alice", "Julia", "Judy", "Sophia", "Grace",
        "Denise", "Amber", "Doris", "Marilyn", "Danielle", "Beverly", "Isabella", "Theresa",
        "Diana", "Natalie", "Brittany", "Charlotte", "Marie", "Kayla", "Alexis", "Lori",
        "Chloe", "Lucy", "Ella", "Mia", "Amelia", "Zoe",
    },
}

function msmIsFemaleSkin(skin)
    return MSM_FEMALE_SKINS[tonumber(skin) or -1] == true
end

-- Random first name matching the skin's gender
function msmRandomName(skin)
    local list = msmIsFemaleSkin(skin) and MSM_NAMES.female or MSM_NAMES.male
    return list[math.random(#list)]
end
