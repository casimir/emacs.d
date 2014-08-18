import java.util.*;
import java.lang.reflect.*;


public class TypeServer {

    private final static Map<Class<?>, Class<?>> map = new HashMap<Class<?>, Class<?>>();
    static {
        map.put(boolean.class, Boolean.class);
        map.put(byte.class, Byte.class);
        map.put(short.class, Short.class);
        map.put(char.class, Character.class);
        map.put(int.class, Integer.class);
        map.put(long.class, Long.class);
        map.put(float.class, Float.class);
        map.put(double.class, Double.class);
    }


    public static void main(String[] args) {
        Scanner inp = new Scanner(System.in);
        while (true) {
            if (!inp.hasNextLine()) continue;
            String line = inp.nextLine();
            String[] words = line.split(" ");
            Object result = false;
            if (words[0].equals("qType")) {
                result = queryType(words[1]);
            } else if (words[0].equals("qConstructor")) {
                result = queryNew(words[1], Arrays.copyOfRange(words, 2, words.length));
            } else if (words[0].equals("qMethod")) {
                result = queryMethod(words[1], words[2], Arrays.copyOfRange(words, 3, words.length));
            } else {
                System.err.println("######## BAD QUERY ########");
            }
            System.out.println(result.toString());
        }
    }

    public static boolean queryType(String classFullName) {
        try {
            Class.forName(classFullName);
        } catch (ClassNotFoundException e) {
            return false;
        }
        return true;
    }


    public static boolean queryNew(String classFullName, String... constructorArgs) {
        try {
            Class<?> c = Class.forName(classFullName);
            Constructor<?>[] cList = c.getConstructors();
            Class<?>[] givenClasses = getClassArray(constructorArgs);
            for (int i = 0; i < cList.length; i++) {
                Class<?>[] actualClasses = cList[i].getParameterTypes();
                if (isArrayAssignableFrom(actualClasses, givenClasses))
                    return true;
            }
            return false;
        } catch (Exception e) {
            return false;
        }
    }


    public static String queryMethod(String classFullName, String methodName, String... methodArgs) {
        String ret;
        try {
            Class<?> c = Class.forName(classFullName);
            Class<?>[] givenClasses = getClassArray(methodArgs);
            Method[] mList = c.getMethods();
            for (int i = 0; i < mList.length; i++) {
                Method m = mList[i];
                if (m.getName().equals(methodName)) {
                    Class<?>[] actualClasses = m.getParameterTypes();
                    if (isArrayAssignableFrom(actualClasses, givenClasses))
                        return classFix(m.getReturnType()).getName();
                }
            }
            return "$";
        } catch (Exception e) {
            return "$";
        }
    }


    private static Class<?>[] getClassArray(String[] names) throws ClassNotFoundException {
        Class<?>[] classes = new Class<?>[names.length];
        for (int i = 0; i < names.length; i++) {
            classes[i] = Class.forName(names[i]);
        }
        return classes;
    }

    // a -> super; b -> sub
    private static boolean isArrayAssignableFrom(Class<?>[] a, Class<?>[] b) {
        if (a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
            if (!classFix(a[i]).isAssignableFrom(classFix(b[i])))
                return false;
        }
        return true;
    }

    // int -> Integer
    private static Class<?> classFix(Class<?> c) {
        return c.isPrimitive() ? map.get(c) : c;
    }
}

