# Fake name and address parts for fork/demo_db/anonymize.rb. Common US names,
# chosen at random by a keyed hash; any that match a real name in the
# database are dropped before use.
module DemoDb
  FEMALE_FIRST = %w[
    Abigail Ada Addison Adeline Alana Alexa Alice Alina Allison Amara Amelia Ana Andrea Angela Anna Ariana Audrey
    Aurora Ava Avery Bailey Bella Brianna Brooke Camila Caroline Cecilia Charlotte Chloe Claire Clara Daisy Delilah
    Diana Eden Elena Eliana Elise Eliza Ella Ellie Eloise Emery Emilia Emma Esther Eva Evelyn Faith Fiona Freya
    Gabriella Gemma Genevieve Georgia Gianna Grace Hadley Hailey Hannah Harper Hazel Heidi Imani Iris Isabel Isla
    Ivy Jade Jasmine Jillian Josephine Julia Juliet June Kaia Katherine Kayla Kendall Kinsley Lacey Laila Lauren
    Layla Leah Leila Lila Lillian Lucia Lucy Luna Lydia Mabel Maeve Margot Maria Marissa Maya Melanie Mila Miriam
    Molly Morgan Naomi Natalie Nora Nova Olivia Paige Penelope Piper Quinn Rachel Reese Rosalie Rose Ruby Sadie
    Samantha Sara Savannah Scarlett Selena Serena Sienna Sofia Stella Sydney Talia Tessa Valerie Vanessa Vera
    Victoria Violet Vivian Willa Willow Zoe Zara
  ].freeze

  MALE_FIRST = %w[
    Aaron Adam Adrian Aiden Alan Alex Andre Andrew Anthony Antonio Arthur Asher Austin Beau Benjamin Bennett Blake
    Brady Brandon Brian Brody Bryce Caleb Calvin Cameron Carlos Carter Cedric Charles Christian Clayton Cole Colin
    Connor Cooper Damian Daniel Darius David Declan Derek Diego Dominic Dylan Easton Edgar Edward Eli Elias Elliot
    Emmett Eric Ethan Evan Ezra Felix Finn Gabriel Gavin George Graham Grayson Harrison Hayden Henry Hudson Ian Isaac
    Ivan Jack Jacob Jaden Jared Jason Jasper Jonah Jordan Joseph Joshua Jude Julian Kai Keith Kevin Kyle Landon Leo
    Leon Levi Liam Lincoln Logan Lucas Luke Malcolm Marcus Mason Mateo Max Micah Miles Nathan Nolan Oliver Omar Oscar
    Owen Parker Patrick Paul Peter Preston Rafael Reid Riley Roman Rowan Ryan Samuel Sawyer Sebastian Silas Simon
    Spencer Theo Thomas Tobias Trevor Tristan Tyler Victor Vincent Wesley Wyatt Xavier Zachary
  ].freeze

  LAST = %w[
    Abbott Acosta Alvarez Andersen Archer Arnold Atkins Avery Bailey Baker Baldwin Barker Barnes Bates Beck Bell
    Benson Bishop Blair Bowen Boyd Bradley Brennan Briggs Brooks Burke Burton Byrd Caldwell Cannon Carlson Carr
    Carroll Carver Castillo Chambers Chandler Chang Christensen Clarke Cobb Coleman Collins Conrad Conway Cortez
    Crawford Cross Curtis Dalton Daniels Davidson Dawson Delgado Dennis Dixon Doyle Drake Dunn Duran Eaton Elliott
    Ellison Emerson Erickson Espinoza Farley Farmer Ferguson Fields Finch Fischer Fleming Fletcher Flores Floyd
    Ford Foster Fowler Francis Frost Fuller Gallagher Garner Garrett Gibbs Gilbert Goodwin Graves Gregory Griffin
    Guerrero Hale Hammond Hansen Hardy Harmon Hart Hawkins Hayes Hendricks Hensley Hicks Hines Hobbs Holland
    Holloway Hopkins Horton Houston Howell Hubbard Hughes Ingram Jacobs Jennings Jensen Keller Kemp Kennedy Kerr
    Kirby Klein Knapp Knox Lambert Lane Larson Lawson Leblanc Lindsey Livingston Lowe Lucero Lyons Mack Maddox
    Malone Mann Marsh Maxwell Mccarthy Mcdaniel Medina Mercer Merritt Meyer Mills Monroe Montgomery Morales
    Moreno Morrow Moss Navarro Newton Nichols Noble Norris Novak Nunez Oconnor Ochoa Odom Oliver Osborne Owens
    Pace Padilla Palmer Park Parsons Patton Pearson Pena Perkins Pierce Porter Powers Pratt Preston Quinn Ramos
    Randall Rasmussen Reese Reeves Rhodes Riggs Rios Rivers Robbins Rocha Rowe Rowland Salas Sandoval Santiago
    Savage Schmidt Schneider Sellers Shaffer Shepherd Sherman Simmons Sloan Snyder Solis Sparks Stafford Stanton
    Steele Stokes Strickland Sullivan Sutton Swanson Tate Terry Thornton Todd Torres Townsend Tucker Underwood
    Vance Vaughn Velasquez Wagner Walsh Walton Warner Watkins Weaver Webster Welch Wheeler Whitaker Wilcox
    Wilkins Winters Wolfe Woodard Wyatt Yates York Young Zamora
  ].freeze

  STREETS = %w[
    Maple Oak Cedar Elm Willow Birch Aspen Juniper Hickory Sycamore Magnolia Chestnut Linden Poplar Spruce Laurel
    Meadow Orchard Prairie Ridge Brookside Lakeview Hillcrest Fairview Sunset Westwood Northfield Stonebridge
    Foxglove Briar Heron Cardinal Bluebird Kestrel Wren Larkspur Clover Thistle Harvest Millstone
  ].freeze

  STREET_SUFFIXES = %w[St Ave Dr Ln Ct Way Rd Pl Cir Trl].freeze

  DIETARY = [
    "Vegetarian", "Vegan", "No pork", "Gluten-free", "Dairy-free", "Peanut allergy", "Tree nut allergy",
    "Shellfish allergy", "No red meat", "Lactose intolerant", "Pescatarian", "No spicy food"
  ].freeze
end
